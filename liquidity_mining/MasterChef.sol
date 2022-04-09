// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./SushiToken.sol";

interface IMigratorChef {
    // 执行从旧版 UniswapV2 到 SushiSwap 的 LP代币(Liquidity Provider Tokens (LP Tokens) 流动性挖矿提供中代币迁移。
    // 取当前 LP 代币地址，返回新的 LP 代币地址。
    // 迁移者应该对调用者的 LP 令牌具有完全访问权限。
    // 返回新的 LP 代币地址。
    //
    // XXX Migrator 必须有权访问 UniswapV2 LP 代币。
    // SushiSwap 必须铸造完全相同数量的 SushiSwap LP 代币
    // 否则会发生不好的事情。传统的 UniswapV2 没有
    // 这样做要小心！
    function migrate(IERC20 token) external returns (IERC20);
}

// MasterChef 来源于Sushi主分支。他可以产生Sushi币，是一个公平的功能。
//
// 请注意，它是可拥有的，并且拥有者拥有巨大的权力。所有权
// 一旦 SUSHI 足够，将转移到治理智能合约
// 分布式，社区可以自我管理。
//
// 祝你阅读愉快。希望它没有错误。上帝保佑。
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    // 每个用户的信息。
    struct UserInfo {
        uint256 amount; // 用户提供了多少 LP 代币。
        uint256 rewardDebt; // 奖励债务。请参阅下面的说明。
        //
        // 我们在这里做一些花哨的数学运算。基本上，任何时间点，SUSHI 的数量
        // 授权给用户，但等待分发的是：
        //
        // 待定奖励 = (user.amount * pool.accSushiPerShare) - user.rewardDebt
        //
        // 每当用户将 LP 代币存入或提取到池中时。这是发生的事情：
        // 1. 池的 `accSushiPerShare`（和 `lastRewardBlock`）得到更新。
        // 2. 用户收到发送到他/她地址的待处理奖励。
        // 3. 用户的 `amount` 被更新。
        // 4. 用户的 `rewardDebt` 得到更新。
    }
    // 每个池的信息。
    struct PoolInfo {
        IERC20 lpToken; // LP代币合约地址。
        uint256 allocPoint; // 分配给这个池的分配点数。SUSHI 按块分配。
        uint256 lastRewardBlock; // SUSHI 分发的最后一个区块号。
        uint256 accSushiPerShare; // 每股累计 SUSHI，乘以 1e12。见下文。
    }
    // The SUSHI TOKEN!
    SushiToken public sushi;
    // Dev address.
    address public devaddr;
    // 红利 SUSHI 期结束时的区块号。
    uint256 public bonusEndBlock;
    // 每个区块创建的 SUSHI 代币。
    uint256 public sushiPerBlock;
    // 早期SUSHI制造商的奖金乘数。
    uint256 public constant BONUS_MULTIPLIER = 10;
    // 迁移者合约。它有很大的力量。只能通过治理（所有者）设置。
    IMigratorChef public migrator;
    // 每个池的信息。
    PoolInfo[] public poolInfo;
    // 每个抵押LP 代币用户的信息
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // 总分配点。必须是所有池中所有分配点的总和。
    uint256 public totalAllocPoint = 0;
    // SUSHI 挖矿开始时的区块号。
    uint256 public startBlock;
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        SushiToken _sushi,
        address _devaddr,
        uint256 _sushiPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) public {
        sushi = _sushi;
        devaddr = _devaddr;
        sushiPerBlock = _sushiPerBlock;
        bonusEndBlock = _bonusEndBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // 添加新的 lp 到池中。只能由所有者调用。
    // XXX 不要多次添加相同的 LP 令牌。如果你这样做了，奖励就会被搞砸。
    // ? : (条件运算符 )
    // 如果条件为真 ? 则取值X : 否则值Y
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accSushiPerShare: 0
            })
        );
    }

    // 更新给定池的 SUSHI 分配点。只能由所有者调用。
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // 设置迁移者合约。只能由所有者调用。
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    // 将 lp 代币迁移到另一个 lp 合约。任何人都可以调用。我们相信移民合同是好的。
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IERC20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }

    // 返回给定 _from 到 _to 块的奖励乘数。
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return _to.sub(_from);
        } else {
            return
                bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                    _to.sub(bonusEndBlock)
                );
        }
    }

    // 查看函数以查看前端挂起的 SUSHI。
    function pendingSushi(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSushiPerShare = pool.accSushiPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number
            );
            uint256 sushiReward = multiplier
                .mul(sushiPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            accSushiPerShare = accSushiPerShare.add(
                sushiReward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accSushiPerShare).div(1e12).sub(user.rewardDebt);
    }

    // 更新所有池的奖励变量。小心油耗！
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // 将给定池的奖励变量更新为最新的。
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 sushiReward = multiplier
            .mul(sushiPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);
        sushi.mint(devaddr, sushiReward.div(10));
        sushi.mint(address(this), sushiReward);
        pool.accSushiPerShare = pool.accSushiPerShare.add(
            sushiReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    // 将 LP 代币存入 MasterChef 用于 SUSHI 分配。
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accSushiPerShare)
                .div(1e12)
                .sub(user.rewardDebt);
            safeSushiTransfer(msg.sender, pending);
        }
        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accSushiPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // 从 MasterChef 中提取 LP 代币。
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accSushiPerShare).div(1e12).sub(
            user.rewardDebt
        );
        safeSushiTransfer(msg.sender, pending);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accSushiPerShare).div(1e12);
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // 退出而不关心奖励。仅限紧急情况。
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // 安全的 sushi 转移函数，以防四舍五入导致池中没有足够的 SUSHI。
    function safeSushiTransfer(address _to, uint256 _amount) internal {
        uint256 sushiBal = sushi.balanceOf(address(this));
        if (_amount > sushiBal) {
            sushi.transfer(_to, sushiBal);
        } else {
            sushi.transfer(_to, _amount);
        }
    }

    // 用前一个开发者更新开发者地址。
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }
}
