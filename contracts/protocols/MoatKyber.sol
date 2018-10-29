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

    function getAddress(string name) internal view returns(address addr) {
        AddressRegistry addrReg = AddressRegistry(addressRegistry);
        return addrReg.getAddr(name);
    }

}


contract Trade is Registry {

    uint public fees;

    event KyberTrade(
        address src,
        uint srcAmt,
        address dest,
        uint destAmt,
        address beneficiary,
        uint fees,
        uint slipRate,
        address affiliate
    );

    // ropsten network
    address public kyberAddr = 0x818E6FECD516Ecc3849DAf6845e3EC868087B755;
    address public eth = 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee;

    function executeTrade(
        address src,
        address dest,
        uint srcAmt,
        uint slipRate
    ) public payable returns (uint destAmt)
    {

        fetchToken(src, srcAmt);
        uint feecut = deductFees(src, srcAmt);

        Kyber kyberFunctions = Kyber(kyberAddr);
        destAmt = kyberFunctions.trade.value(msg.value)(
            src,
            srcAmt - feecut,
            dest,
            msg.sender,
            2**256 - 1,
            slipRate,
            getAddress("admin")
        );

        emit KyberTrade(
            src,
            srcAmt,
            dest,
            destAmt,
            msg.sender,
            feecut,
            slipRate,
            getAddress("admin")
        );

    }

    function fetchToken(address src, uint srcAmt) internal {
        if (src != eth) {
            IERC20 tokenFunctions = IERC20(src);
            tokenFunctions.transferFrom(msg.sender, address(this), srcAmt);
        }
    }

    function deductFees(address src, uint volume) internal returns(uint brokerage) {
        if (fees > 0) {
            brokerage = volume / fees;
            if (src == eth) {
                getAddress("admin").transfer(brokerage);
            } else {
                IERC20 tokenFunctions = IERC20(src);
                tokenFunctions.transfer(getAddress("admin"), brokerage);
            }
        }
    }

    function allowKyber(address[] tokenArr) public {
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
        if (tokenAddress == eth) {
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
