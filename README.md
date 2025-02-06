# Mechanism

1. (Relative Stability) Anchored or Pegged -> $1.00
   1. Chainlink Price feed
   2. Set a function to exchange ETH & BTC -> $$$
2. Stability Mechanism(Minting): Algorithmic(Decentralized)
   1. People can only mint stablecoin with enough collateral (coded)
3. Collateral : Exogenous (Crypto)
   1. wETH
   2. wBTC

# Question

1. What are our invariants/properties? --> fuzz / invariant test symbolic execution / formal verification ===> Handler based m

# Getting Started

意在实现了一个去中心化的稳定币系统。该系统的主要目标是保持稳定币与美元的 1:1 锚定，并通过超额抵押的方式来确保系统的稳定性。

## `DecentralizedStableCoin.sol`:

这是一个 ERC20 代币合约，代表去中心化的稳定币（DSC）。
该合约允许铸造（mint）和销毁（burn）稳定币，并且只有合约的所有者（DSCEngine 合约）可以执行这些操作。
该合约还继承了 ERC20Burnable 和 Ownable 合约，提供了代币的基本功能和所有权管理
。

## `DSCEngine.sol`:

这是系统的核心合约，负责管理抵押品的存入和取出、稳定币的铸造和销毁、以及清算机制。
该合约使用 Chainlink 的价格预言机来获取抵押品的实时价格，并根据抵押品的价值来确保系统始终处于超额抵押状态。
该合约还实现了健康因子（Health Factor）的计算，用于监控用户的抵押品是否足够，并在抵押品不足时触发清算。

1. `constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress)`
   功能: 初始化 DSCEngine 合约，设置支持的抵押品代币及其对应的价格预言机地址，并设置稳定币合约地址。
   参数:
   tokenAddresses: 支持的抵押品代币地址数组。
   priceFeedAddresses: 对应的价格预言机地址数组。
   dscAddress: 稳定币合约地址。

2. `despositCollateralAndMintDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint)`
   功能: 存入抵押品并铸造稳定币。这是一个组合操作，先存入抵押品，然后铸造稳定币。
   参数:
   tokenCollateralAddress: 抵押品代币地址。
   amountCollateral: 存入的抵押品数量。
   amountDscToMint: 要铸造的稳定币数量。

3. `depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)`
   功能: 存入抵押品。
   参数:
   tokenCollateralAddress: 抵押品代币地址。
   amountCollateral: 存入的抵押品数量。

4. `redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDSCToBurn)`
   功能: 赎回抵押品并销毁稳定币。这是一个组合操作，先销毁稳定币，然后赎回抵押品。
   参数:
   tokenCollateralAddress: 抵押品代币地址。
   amountCollateral: 赎回的抵押品数量。
   amountDSCToBurn: 要销毁的稳定币数量。

5. `redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)`
   功能: 赎回抵押品。
   参数:
   tokenCollateralAddress: 抵押品代币地址。
   amountCollateral: 赎回的抵押品数量。

6. `mintDSC(uint256 amountDscToMint)`
   功能: 铸造稳定币。
   参数:
   amountDscToMint: 要铸造的稳定币数量。

7. `burnDSC(uint256 amount)`
   功能: 销毁稳定币。
   参数:
   amount: 要销毁的稳定币数量。

8. `liquidate(address collateralAddress, address user, uint256 debtToCover)`
   功能: 清算用户的抵押品。当用户的健康因子低于最低要求时，其他用户可以调用此函数来清算该用户的抵押品，并获得清算奖励。
   参数:
   collateralAddress: 抵押品代币地址。
   user: 被清算的用户地址。
   debtToCover: 要覆盖的债务数量。

9. `_revertIfHealthFactorBroken(address user)`
   功能: 检查用户的健康因子，如果低于最低要求则回滚交易。
   参数:
   user: 要检查的用户地址。

10. `_healthFactor(address user)`
    功能: 计算用户的健康因子。
    参数:
    user: 要计算的用户地址。
    返回值: 健康因子（1e18 精度）。

11. `_calculateHealthFactor(uint256 collateralValueOfUsd, uint256 amountDSC)`
    功能: 计算健康因子。
    参数:
    collateralValueOfUsd: 抵押品的总价值（USD）。
    amountDSC: 已铸造的稳定币数量。
    返回值: 健康因子（1e18 精度）。

12. `_getAccountInfomation(address user)`
    功能: 获取用户的账户信息，包括已铸造的稳定币数量和抵押品的总价值。
    参数:
    user: 要查询的用户地址。
    返回值:
    totalDscMinted: 已铸造的稳定币数量。
    collateralValueOfUsd: 抵押品的总价值（USD）。

13. `_redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)`
    功能: 内部函数，用于赎回抵押品。
    参数:
    tokenCollateralAddress: 抵押品代币地址。
    amountCollateral: 赎回的抵押品数量。
    from: 抵押品的来源地址。
    to: 抵押品的接收地址。

14. `_burnDSC(uint256 amount, address onBehalf, address dscFromWho)`
    功能: 内部函数，用于销毁稳定币。
    参数:
    amount: 要销毁的稳定币数量。
    onBehalf: 代表谁销毁稳定币。
    dscFromWho: 从谁那里销毁稳定币。

15. `getTokenAmountFromUsd(address token, uint256 amountUsdInWei)`
    功能: 根据 USD 价值计算对应代币的数量。
    参数:
    token: 代币地址。
    amountUsdInWei: USD 价值（1e18 精度）。
    返回值: 代币数量（1e18 精度）。

16. `getAccountCollateralValueOfUsd(address user)`
    功能: 获取用户抵押品的总价值（USD）。
    参数:
    user: 要查询的用户地址。
    返回值: 抵押品的总价值（1e18 精度）。

17. `getEachCollateralUsdValue(address token, uint256 amount)`
    功能: 获取指定代币数量的 USD 价值。
    参数:
    token: 代币地址。
    amount: 代币数量。
    返回值: USD 价值（1e18 精度）。

18. `getAccountInfomation(address user)`
    功能: 获取用户的账户信息，包括已铸造的稳定币数量和抵押品的总价值。
    参数:
    user: 要查询的用户地址。
    返回值:
    totalDscMinted: 已铸造的稳定币数量。
    collateralValueOfUsd: 抵押品的总价值（USD）。

19. `getCollateralAmount(address user, address token)`
    功能: 获取用户指定抵押品的数量。
    参数:
    user: 要查询的用户地址。
    token: 抵押品代币地址。
    返回值: 抵押品数量。

20. `getHealthFactor(address user)`
    功能: 获取用户的健康因子。
    参数:
    user: 要查询的用户地址。
    返回值: 健康因子（1e18 精度）。

21. `calculateHealthFactor(uint256 collateralValueOfUsd, uint256 amountDSC)`
    功能: 计算健康因子。
    参数:
    collateralValueOfUsd: 抵押品的总价值（USD）。
    amountDSC: 已铸造的稳定币数量。
    返回值: 健康因子（1e18 精度）。

22. `getMinimumHealthFactor()`
    功能: 获取最低健康因子。
    返回值: 最低健康因子（1e18 精度）。

23. `getLiquidationBonus()`
    功能: 获取清算奖励比例。
    返回值: 清算奖励比例。

24. `getCollateralAddresses()`
    功能: 获取所有支持的抵押品代币地址。
    返回值: 抵押品代币地址数组。

25. `getCollateralPriceFeed(address token)`
    功能: 获取指定抵押品代币的价格预言机地址。
    参数:
    token: 抵押品代币地址。
    返回值: 价格预言机地址。
