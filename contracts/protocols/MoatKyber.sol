pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";


interface AddressRegistry {
    function getAddr(string name) external returns(address);
    function isApprovedResolver(address user) external returns(bool);
}

interface Resolver {
    function fees() external returns(uint);
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

    address public registryAddress;

    modifier onlyUserOrResolver(address user) {
        if (msg.sender != user) {
            require(
                msg.sender == getAddress("resolver"),
                "Permission Denied"
            );
            AddressRegistry addrReg = AddressRegistry(registryAddress);
            require(
                addrReg.isApprovedResolver(user),
                "Resolver Not Approved"
            );
        }
        _;
    }

    modifier onlyAdmin() {
        require(
            msg.sender == getAddress("admin"),
            "Permission Denied"
        );
        _;
    }

    function getAddress(string name) internal view returns(address addr) {
        AddressRegistry addrReg = AddressRegistry(registryAddress);
        addr = addrReg.getAddr(name);
        require(addr != address(0), "Invalid Address");
    }

}


contract Trade is Registry {

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
    address public eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function executeTrade(
        address trader,
        address src,
        address dest,
        uint srcAmt,
        uint slipRate
    ) public payable onlyUserOrResolver(trader) returns (uint destAmt)
    {

        fetchToken(trader, src, srcAmt);
        uint fees = deductFees(src, srcAmt);

        Kyber kyberFunctions = Kyber(kyberAddr);
        destAmt = kyberFunctions.trade.value(msg.value)(
            src,
            srcAmt - fees,
            dest,
            trader,
            2**256 - 1,
            slipRate,
            getAddress("admin")
        );

        emit KyberTrade(
            src,
            srcAmt,
            dest,
            destAmt,
            trader,
            fees,
            slipRate,
            getAddress("admin")
        );

    }

    function fetchToken(address trader, address src, uint srcAmt) internal {
        if (src != eth) {
            IERC20 tokenFunctions = IERC20(src);
            tokenFunctions.transferFrom(trader, address(this), srcAmt);
        }
    }

    function deductFees(address src, uint volume) internal returns(uint fees) {
        Resolver moatRes = Resolver(getAddress("resolver"));
        fees = moatRes.fees();
        if (fees > 0) {
            fees = volume / fees;
            if (src == eth) {
                getAddress("admin").transfer(fees);
            } else {
                IERC20 tokenFunctions = IERC20(src);
                tokenFunctions.transfer(getAddress("admin"), fees);
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
        registryAddress = rAddr;
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

}
