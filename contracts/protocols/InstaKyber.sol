pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";


interface AddressRegistry {
    function getAddr(string name) external view returns(address);
}

interface Kyber {
    function trade(
        address src,
        uint srcAmount,
        address dest,
        address destAddress,
        uint maxDestAmount,
        uint minConversionRate,
        address walletId
    ) external payable returns (uint);

    function getExpectedRate(
        address src,
        address dest,
        uint srcQty
    ) external view returns (uint, uint);
}


contract Registry {
    address public addressRegistry;
    modifier onlyAdmin() {
        require(
            msg.sender == getAddress("admin"),
            "Permission Denied"
        );
        _;
    }
    function getAddress(string name) internal view returns(address) {
        AddressRegistry addrReg = AddressRegistry(addressRegistry);
        return addrReg.getAddr(name);
    }

}


contract Trade is Registry {

    using SafeMath for uint;
    using SafeMath for uint256;

    event KyberTrade(
        address src,
        uint srcAmt,
        address dest,
        uint destAmt,
        address beneficiary,
        uint minConversionRate,
        uint fees,
        address affiliate
    );

    // Market & Limit Order
    // tradeAdmin manages the orders on behalf of client
    // @param "client" is mainly for limit orders (and it can also be used for server-side market orders)
    function executeTrade(
        address src,
        address dest,
        uint srcAmt,
        uint minConversionRate,
        address client
    ) public payable returns (uint destAmt)
    {

        address trader = msg.sender;
        if (client != address(0x0)) {
            require(msg.sender == getAddress("tradeAdmin"), "Permission Denied");
            trader = client;
        }

        // transferring token from trader and deducting fee if applicable
        uint ethQty;
        uint srcAmtAfterFees;
        uint fees;
        (ethQty, srcAmtAfterFees, fees) = getToken(
            trader,
            src,
            srcAmt,
            client
        );
        
        // Interacting with Kyber Proxy Contract
        Kyber kyberFunctions = Kyber(getAddress("kyber"));
        destAmt = kyberFunctions.trade.value(ethQty)(
            src,
            srcAmtAfterFees,
            dest,
            trader,
            2**256 - 1,
            minConversionRate,
            getAddress("admin")
        );

        emit KyberTrade(
            src,
            srcAmtAfterFees,
            dest,
            destAmt,
            trader,
            minConversionRate,
            fees,
            getAddress("admin")
        );

    }

    function getExpectedPrice(
        address src,
        address dest,
        uint srcAmt
    ) public view returns (uint, uint) 
    {
        Kyber kyberFunctions = Kyber(getAddress("kyber"));
        return kyberFunctions.getExpectedRate(
            src,
            dest,
            srcAmt
        );
    }

    function approveKyber(address[] tokenArr) public {
        for (uint i = 0; i < tokenArr.length; i++) {
            IERC20 tokenFunctions = IERC20(tokenArr[i]);
            tokenFunctions.approve(getAddress("kyber"), 2**256 - 1);
        }
    }

    function getToken(
        address trader,
        address src,
        uint srcAmt,
        address client
    ) internal returns (
        uint ethQty,
        uint srcAmtAfterFees,
        uint fees
    ) 
    {
        if (src == getAddress("eth")) {
            require(msg.value == srcAmt, "Invalid Operation");
            ethQty = srcAmt;
        } else {
            IERC20 tokenFunctions = IERC20(src);
            tokenFunctions.transferFrom(trader, address(this), srcAmt);
            ethQty = 0;
        }

        srcAmtAfterFees = srcAmt;
        if (client != address(0x0)) {
            fees = srcAmt / 400; // 0.25%
            srcAmtAfterFees = srcAmt - fees;
            if (ethQty > 0) {
                ethQty = srcAmtAfterFees;
            }
        }
    }

}


contract InstaKyber is Trade {

    event FeesCollected(address tokenAddr, uint amount);

    constructor(address rAddr) public {
        addressRegistry = rAddr;
    }

    function () public payable {}

    function collectFees(address tokenAddress, uint amount) public onlyAdmin {
        if (tokenAddress == getAddress("eth")) {
            msg.sender.transfer(amount);
        } else {
            IERC20 tokenFunctions = IERC20(tokenAddress);
            tokenFunctions.transfer(msg.sender, amount);
        }
        emit FeesCollected(tokenAddress, amount);
    }

}