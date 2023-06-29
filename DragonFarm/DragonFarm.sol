/**
 *Submitted for verification at BscScan.com on 2023-06-11
*/

pragma solidity ^0.8.0;



contract DragonFarm {
    using SafeMath for uint256;

// 龙结构体，包含龙的各种属性信息
struct Dragon {
    uint256 food;           // 食物数量
    uint256 gold;           // 金币数量
    uint256 yield;          // 收益
    uint256 level;          // 等级
    uint256 class;          // 类别
    uint256 lastUpgrade;    // 上次升级时间戳
}

// 用户结构体，包含用户的各种信息和龙的信息
struct User {
    uint256 checkpoint;             // 检查点，用于记录用户最后一次同步龙信息的时间戳
    uint256 totalDeposited;         // 总存款金额
    uint256 totalWithdrawn;         // 总提现金额
    uint256[15] refRewards;         // 推荐奖励数组，存储不同级别的推荐奖励金额
    uint256[15] referrals;          // 推荐人数组，存储不同级别的推荐人数量
    address referrer;               // 推荐人地址
    Dragon dragon;                  // 龙的信息，是一个 Dragon 结构体类型的变量，包含龙的各种属性
}

    modifier notContract {
        require(!isContract(msg.sender), "caller is a contract");
        _;
    }



    event dragonHatched(uint256 dragonType, address indexed userAddress, uint256 timestamp);
    event foodBought(uint256 foodAmount, address indexed userAddress, uint256 timestamp);
    event dragonUpgraded(uint256 lvl, address indexed userAddress, uint256 timestamp);
    event goldSold(uint256 etherAmount, address indexed userAddress, uint256 timestamp);
    event goldCollected(uint256 goldAmount, address indexed userAddress, uint256 timestamp);

    constructor(address marketingAddress, address devAddress) {
        require(!isContract(marketingAddress));
        require(!isContract(devAddress));
        marketingFund = marketingAddress;
        dev = devAddress;
    }

    function launch() public {
        require(msg.sender == dev);

        launched = true;
    }

    function hatchDragon(uint256 dragonType, address referrer) public notContract {
         // 检查合约是否已经启动
        require(launched, "合约尚未启动");
        
        // 检查调用者是否已经孵化了龙
        require(users[msg.sender].dragon.class == 0, "已经孵化了龙");
        
        // 检查传入的龙的类型是否大于0
        require(dragonType > 0, "必须大于0");
        
        // 检查传入的龙的类型是否小于5
        require(dragonType < 5, "必须小于5");
        
        // 检查推荐人是否不是调用者本身
        require(referrer != msg.sender, "错误的推荐人");
        
        // 获取调用者的用户信息
        User storage user = users[msg.sender];

        // 如果传入的推荐人不是零地址并且推荐人已经孵化了龙，将其设置为调用者的推荐人
        if(referrer != address(0) && users[referrer].dragon.class != 0) {
            user.referrer = referrer;
        } 

        // 将调用者的推荐人地址赋值给局部变量 upline
        address upline = user.referrer;

        // 循环遍历15次
        for(uint256 i = 0; i < 15; i++) {
            // 如果 upline 不是零地址
            if(upline != address(0)) {
                // 将 upline 用户的第 i 个推荐数量增加1
                users[upline].referrals[i] = users[upline].referrals[i].add(1);
                // 将 upline 更新为 upline 用户的推荐人地址
                upline = users[upline].referrer;
            } else {
                // 如果 upline 是零地址，跳出循环
                break;
            }
        }

        // 设置调用者的龙的属性
        user.dragon.class = dragonType;
        user.dragon.food = 1000;
        user.dragon.level = 1;
        user.dragon.yield = getYieldByLevel(1);
        user.checkpoint = block.timestamp;
        user.dragon.lastUpgrade = block.timestamp;

        // 增加对应类型的龙的数量
        dragons[dragonType] = dragons[dragonType].add(1);

        // 触发龙孵化事件
        emit dragonHatched(dragonType, msg.sender, block.timestamp);
    }


        ffunction buyFood() public payable notContract {
        // 检查支付的金额是否达到最低购买限制
        require(msg.value >= MIN_PURCHASE, "金额不足");

        // 调用 _buyFood 函数进行购买食物操作
        _buyFood(msg.value, msg.sender);
    }

    function _buyFood(uint256 value, address sender) private {
        // 检查购买者是否已经孵化了龙
        require(users[sender].dragon.class > 0, "龙尚未孵化");

        // 计算购买的食物数量
        uint256 foodAmount = value.div(FOOD_PRICE);

        // 同步购买者的龙信息
        syncDragon(sender);

        // 支付手续费
        payFee(value);

        // 增加购买者的食物数量
        users[sender].dragon.food = users[sender].dragon.food.add(foodAmount);

        // 更新总质押金额和总存款数
        totalStaked = totalStaked.add(value);
        totalDeposits = totalDeposits.add(1);

        // 增加对应类型的龙的数量
        dragons[users[sender].dragon.class] = dragons[users[sender].dragon.class].add(1);

        // 增加购买者的总存款金额
        users[sender].totalDeposited = users[sender].totalDeposited.add(value);

        // 触发购买食物事件
        emit foodBought(foodAmount, sender, block.timestamp);
    }

    function buyFoodForGold() public notContract {
        // 检查购买者是否拥有金币
        require(users[msg.sender].dragon.gold > 0, "金币数量为零");

        // 计算金币兑换为以太币的金额，并考虑金币到食物的额外奖励
        uint256 goldToEther = users[msg.sender].dragon.gold.mul(GOLD_PRICE);
        uint256 amountWithBonus = goldToEther.add(goldToEther.mul(GOLD_TO_FOOD_BONUS).div(PERCENTS_DIVIDER));

        // 清空购买者的金币数量
        users[msg.sender].dragon.gold = 0;

        // 使用 _buyFood 函数进行购买食物操作
        _buyFood(amountWithBonus, msg.sender);
    }

    function sellGold() public payable notContract {
        // 检查卖出者是否已经孵化了龙
        require(users[msg.sender].dragon.class > 0, "龙尚未孵化");

        // 检查卖出者是否拥有金币
        require(users[msg.sender].dragon.gold > 0, "金币数量为零");

        // 计算应支付的金额
        uint256 payout = users[msg.sender].dragon.gold.mul(GOLD_PRICE);

        // 检查支付的金额是否达到最低提现限制
        require(payout >= MIN_WITHDRAWAL, "金额不足");

        // 如果支付的金额超过了合约当前的余额，将支付金额调整为合约当前的余额
        if(payout > address(this).balance) {
            payout = address(this).balance;
        }

        // 清空卖出者的金币数量
        users[msg.sender].dragon.gold = 0;

        // 增加卖出者的总提现金额
        users[msg.sender].totalWithdrawn = users[msg.sender].totalWithdrawn.add(payout);

        // 支付推荐奖励
        payRefRewards(msg.sender, payout);

        // 将支付的金额转账给卖出者
        payable(msg.sender).transfer(payout);

        // 触发金币卖出事件
        emit goldSold(payout, msg.sender, block.timestamp);
    }


    function collectGold() public notContract {
    // 检查调用者是否已经孵化了龙
        require(users[msg.sender].dragon.class > 0, "龙尚未孵化");

        // 记录收集金币前的金币数量
        uint256 goldBefore = users[msg.sender].dragon.gold;

        // 同步调用者的龙信息
        syncDragon(msg.sender);

        // 记录收集金币后的金币数量
        uint256 goldAfter = users[msg.sender].dragon.gold;

        // 计算本次收集的金币数量
        uint256 totalCollected = goldAfter.sub(goldBefore);

        // 增加总收益金额
        totalEarned = totalEarned.add(totalCollected.mul(GOLD_PRICE));

        // 触发金币收集事件
        emit goldCollected(totalCollected, msg.sender, block.timestamp);
    }

    function upgradeDragon() public notContract {
        // 检查调用者是否已经孵化了龙
        require(users[msg.sender].dragon.class > 0, "龙尚未孵化");

        // 检查调用者的龙是否还有升级的空间
        require(users[msg.sender].dragon.level < 40, "龙已达到最高级别");

        // 检查升级时间间隔是否满足条件
        bool upgradable = block.timestamp.sub(users[msg.sender].dragon.lastUpgrade) >= DRAGON_UPGRADE_TIME ? true : false;
        require(upgradable, "每天只能升级一次");

        // 获取调用者的用户信息
        User storage user = users[msg.sender];

        // 同步调用者的龙信息
        syncDragon(msg.sender);

        // 增加调用者的龙级别
        user.dragon.level = user.dragon.level.add(1);

        // 根据新的级别获取调用者的龙收益
        user.dragon.yield = getYieldByLevel(user.dragon.level);

        // 更新调用者的龙升级时间
        user.dragon.lastUpgrade = block.timestamp;

        // 触发龙升级事件
        emit dragonUpgraded(user.dragon.level, msg.sender, block.timestamp);
    }


    
    
    
    
        function payFee(uint256 amount) private {
            // 计算营销费用和开发费用
            uint256 marketingFee = amount.mul(MARKETING_FEE).div(PERCENTS_DIVIDER);
            uint256 devFee = amount.mul(DEV_FEE).div(PERCENTS_DIVIDER);

            // 将营销费用转账给营销基金账户
            payable(marketingFund).transfer(marketingFee);
            // 将开发费用转账给开发者账户
            payable(dev).transfer(devFee);
    }

    function payRefRewards(address userAddress, uint256 value) private {
        // 获取用户信息
        User storage user = users[userAddress];

        // 检查用户是否有推荐人
        if (user.referrer != address(0)) {
            // 获取推荐链上的推荐人
            address upline = user.referrer;

            for (uint256 i = 0; i < 15; i++) {
                if (upline != address(0)) {
                    // 计算推荐奖励金额
                    uint256 amount = value.mul(getRefRewards(i)).div(PERCENTS_DIVIDER);

                    // 将推荐奖励转换为金币数量
                    uint256 goldAmount = amount.div(GOLD_PRICE);

                    // 增加推荐人的推荐奖励和金币数量
                    users[upline].refRewards[i] = users[upline].refRewards[i].add(goldAmount);
                    users[upline].dragon.gold = users[upline].dragon.gold.add(goldAmount);

                    // 更新推荐链上的推荐人为下一个推荐人
                    upline = users[upline].referrer;
                } else {
                    break;
                }
            }
        }
    }

    function syncDragon(address userAddress) private {
        // 检查用户的检查点是否大于0
        if (users[userAddress].checkpoint > 0) {
            // 将食物数量转换为以太币金额
            uint256 foodToEther = users[userAddress].dragon.food.mul(FOOD_PRICE);
            // 计算用户的份额
            uint256 share = foodToEther.mul(users[userAddress].dragon.yield).div(PERCENTS_DIVIDER);
            // 计算计算周期的起始时间和结束时间
            uint256 from = users[userAddress].checkpoint;
            uint256 to = block.timestamp;
            // 计算总金额
            uint256 totalAmount = share.mul(to.sub(from)).div(TIME_STEP);
            // 将金额转换为金币数量
            uint256 goldAmount = totalAmount.div(GOLD_PRICE);

            if (goldAmount > 0) {
                // 增加用户的金币数量
                users[userAddress].dragon.gold = users[userAddress].dragon.gold.add(goldAmount);
            }
        }

        // 更新用户的检查点为当前时间戳
        users[userAddress].checkpoint = block.timestamp;
    }

    function getYieldByLevel(uint256 level) internal pure returns (uint256) {
        // 返回根据等级确定的收益值
        return [0, 250, 255, 260, 265, 270, 275, 280, 285, 290, 295, 300, 305, 310, 315, 320, 325, 330, 335, 340, 345, 350, 355, 360, 365, 370, 375, 380, 385, 390, 395, 400, 405, 410, 415, 420, 425, 430, 435, 440, 445][level];
    }

    function getRefRewards(uint256 index) internal pure returns (uint256) {
        // 返回根据索引确定的推荐奖励值
        return [1000, 1000, 600, 600, 400, 400, 300, 300, 200, 200, 100, 100, 100, 50, 50][index];
    }

    function getUserDragon(address userAddress) public view returns (Dragon memory) {
        // 返回用户的龙信息
        return users[userAddress].dragon;
    }

    function getUpgradeTimer(address userAddress) public view returns (uint256) {
        // 计算距离下次升级的剩余时间
        return block.timestamp.sub(users[userAddress].dragon.lastUpgrade) > DRAGON_UPGRADE_TIME ? 0 : DRAGON_UPGRADE_TIME.sub(block.timestamp.sub(users[userAddress].dragon.lastUpgrade));
    }

    function getUserPendingGold(address userAddress) public view returns (uint256) {
        // 计算用户待领取的金币数量
        uint256 foodToEther = users[userAddress].dragon.food.mul(FOOD_PRICE);
        uint256 share = foodToEther.mul(users[userAddress].dragon.yield).div(PERCENTS_DIVIDER);
        uint256 from = users[userAddress].checkpoint;
        uint256 to = block.timestamp;
        uint256 totalAmount = share.mul(to.sub(from)).div(TIME_STEP);
        return totalAmount.div(GOLD_PRICE);
    }

    function getUserInfo(address userAddress) public view returns (uint256 deposited, uint256 withdrawn, uint256[15] memory _referrals, uint256[15] memory _refRewards, address _referrer) {
        // 返回用户的信息
        deposited = users[userAddress].totalDeposited;
        withdrawn = users[userAddress].totalWithdrawn;
        _referrals = users[userAddress].referrals;
        _refRewards = users[userAddress].refRewards;
        _referrer = users[userAddress].referrer;
    }

    function getDragons() public view returns (uint256 type1, uint256 type2, uint256 type3, uint256 type4) {
        // 返回不同类型龙的数量
        type1 = dragons[1];
        type2 = dragons[2];
        type3 = dragons[3];
        type4 = dragons[4];
    }

    function getContractInfo() public view returns (uint256 _totalDeposits, uint256 _totalStaked, uint256 _totalEarned) {
        // 返回合约的信息
        _totalDeposits = totalDeposits;
        _totalStaked = totalStaked;
        _totalEarned = totalEarned;
    }

    function isContract(address account) internal view returns (bool) {
        // 检查地址是否为合约地址
        return account.code.length > 0;
    }


library SafeMath {

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        uint256 c = a / b;

        return c;
    }
    
     function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0);
        return a % b;
    }
}