pragma solidity ^0.6.6;

import "../UniswapV2Library.sol";
import "../interfaces/IUniswapV2Router02.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IUniswapV2Factory.sol";
import "../interfaces/IERC20.sol";

contract Arbitrage {
    // factory saves uniswap pool cryptocurrencies pairs
    address public factory;
    uint256 constant deadline = 10 days;
    
    // sushi router is used to make pair transactions with sushiswap
    // sushiSwap is a fork of uniswap, so uniswap interface has the same function
    IUniswapV2Router02 public sushiRouter;

    constructor(address _factory, address _sushiRouter) public {
        factory = _factory;
        sushiRouter = IUniswapV2Router02(_sushiRouter);
    }


// amount0 or amount 1 must be 0. The variable greater than 0 would be requested for a flashloan
    function startArbitrage(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) external {
        // Get uniSwap pool's pair address to request a pair flashLoan
        address pairAddress = IUniswapV2Factory(factory).getPair(
            token0,
            token1
        );

        // Test is address is not null
        require(pairAddress != address(0), "This pool does not exist");
         
        // Request flashLoan for the requested pair address
        // The last parameter is added so the uniSwap contract understands it is a flashloan
        // FlashLoans are not requested from a router (like the declared for sushiSwap). It is requested directly from the interface
        IUniswapV2Pair(pairAddress).swap(
            amount0,
            amount1,
            address(this),
            bytes("not empty")
        );
    }

    // This is the uniswap default callback function name that is called when a flashLoan is requested from a contract
    function uniswapV2Call(
        address _sender,
        uint256 _amount0,
        uint256 _amount1,
        bytes calldata _data
    ) external {
        address[] memory path = new address[](2);

        // Amount that is going to be requested
        uint256 amountToken = _amount0 == 0 ? _amount1 : _amount0;

        // Address of both ierc20 token
        address token0 = IUniswapV2Pair(msg.sender).token0();
        address token1 = IUniswapV2Pair(msg.sender).token1();

        // Test if the tokens pair address is the one that call our callback function
        require(
            msg.sender == UniswapV2Library.pairFor(factory, token0, token1),
            "Unauthorized"
        );
        // Check if there is a 0 amount (must be)
        require(_amount0 == 0 || _amount1 == 0);

        // Save the ierc20 tokens address
        // Path[0] (token we are selling)
        // Path[1] (token we are buying)
        path[0] = _amount0 == 0 ? token1 : token0;
        path[1] = _amount0 == 0 ? token0 : token1;

        // Create a token interface for the requested ierc20 token address loan
        IERC20 token = IERC20(_amount0 == 0 ? token1 : token0);

        // Aprove the sushiSwap router to make a transaction on behalf of this 
        // contract's address for a total of the requested flashLoan
        token.approve(address(sushiRouter), amountToken);

        // Get total amount that must be reimbursed to uniSwap after the flashloan
        uint256 amountRequired = UniswapV2Library.getAmountsIn(
            factory,
            amountToken,
            path
        )[0];

        // Swap on sushiSwap for an amount of amountToken over path[0] expecting equal or more than amountRequired on path[1]
        // and send it to this contract address
        // deadline variable is not important here because this is a flash movement. it will be calceled if takes to long
        uint256 amountReceived = sushiRouter.swapExactTokensForTokens(
            amountToken,
            amountRequired,
            path,
            address(this),
            deadline
        )[1];


        // Create an interface of the bougth token
        IERC20 otherToken = IERC20(_amount0 == 0 ? token0 : token1);
        
        // Send required amount of the bougth token on sushiSwap to uniSwap
        otherToken.transfer(msg.sender, amountRequired);

        // Transfer the one who called "startArbitrage" the gains
        otherToken.transfer(tx.origin, amountReceived - amountRequired);
    }
}
