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

    uint public fees;

    event KyberTrade(
        address src,
        uint srcAmt,
        address dest,
        uint destAmt,
        address beneficiary,
        uint feecut,
        uint minConversionRate,
        address affiliate
    );

    function executeTrade(
        address src,
        address dest,
        uint srcAmt,
        uint minConversionRate
    ) public payable returns (uint destAmt)
    {
        address protocolAdmin = getAddress("admin");
        uint sellQty = srcAmt;
        uint ethQty;
        uint feecut;
        if (fees > 0) {
            feecut = srcAmt.div(fees);
            sellQty = srcAmt.sub(feecut);
        }

        // fetch token & deduct fees
        IERC20 tokenFunctions = IERC20(src);
        if (src == getAddress("eth")) {
            require(msg.value == srcAmt, "Invalid Operation");
            if (feecut > 0) {protocolAdmin.transfer(feecut);}
            ethQty = sellQty;
        } else {
            tokenFunctions.transferFrom(msg.sender, address(this), srcAmt);
            if (feecut > 0) {tokenFunctions.transfer(protocolAdmin, feecut);}
        }

        Kyber kyberFunctions = Kyber(getAddress("kyber"));
        destAmt = kyberFunctions.trade.value(ethQty)(
            src,
            sellQty,
            dest,
            msg.sender,
            2**256 - 1,
            minConversionRate,
            protocolAdmin
        );

        emit KyberTrade(
            src,
            srcAmt,
            dest,
            destAmt,
            msg.sender,
            feecut,
            minConversionRate,
            protocolAdmin
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

}


contract MoatKyber is Trade {

    constructor(address rAddr) public {
        addressRegistry = rAddr;
    }

    function () public payable {}

    function collectAsset(address tokenAddress, uint amount) public onlyAdmin {
        if (tokenAddress == getAddress("eth")) {
            msg.sender.transfer(amount);
        } else {
            IERC20 tokenFunctions = IERC20(tokenAddress);
            tokenFunctions.transfer(msg.sender, amount);
        }
    }

    function setFees(uint cut) public onlyAdmin { // 200 means 0.5%
        fees = cut;
    }

}