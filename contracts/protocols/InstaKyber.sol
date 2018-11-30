pragma solidity ^0.4.24;


library SafeMath {

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "Assertion Failed");
        return c;
    }
    
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "Assertion Failed");
        uint256 c = a / b;
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "Assertion Failed");
        uint256 c = a - b;
        return c;
    }

}

interface IERC20 {
    function balanceOf(address who) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

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
        address referral,
        uint cut,
        address partner
    );

    address public eth = 0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee;

    function getExpectedPrice(
        address src,
        address dest,
        uint srcAmt
    ) public view returns (uint, uint) 
    {
        Kyber kyberFunctions = Kyber(getAddress("kyber"));
        return kyberFunctions.getExpectedRate(
            src, dest, srcAmt
        );
    }

    function approveKyber(address[] tokenArr) public {
        address kyberProxy = getAddress("kyber");
        for (uint i = 0; i < tokenArr.length; i++) {
            IERC20 tokenFunctions = IERC20(tokenArr[i]);
            tokenFunctions.approve(kyberProxy, 2**256 - 1);
        }
    }

    struct TradeUints {
        uint srcAmt;
        uint ethQty;
        uint srcAmtWithFees;
        uint cut;
        uint destAmt;
        int ethBalAfterTrade; // it can be neagtive
    }

    function executeTrade(
        address src, // token to sell
        address dest, // token to buy
        uint srcAmt, // amount of token for sell
        uint srcAmtWithFees, // amount of token for sell + fees // equal or greater than srcAmt
        uint minConversionRate, // minimum slippage rate
        uint maxDestAmt, // max amount of dest token
        address partner // affiliate partner
    ) public payable returns (uint destAmt)
    {

        require(srcAmtWithFees >= srcAmt, "srcAmtWithFees can't be small than scrAmt");
        if (src == eth) {
            require(srcAmtWithFees == msg.value, "Not enough ETH to cover the trade.");
        }

        TradeUints memory tradeSpecs;
        Kyber kyberFunctions = Kyber(getAddress("kyber"));

        tradeSpecs.srcAmt = srcAmt;
        tradeSpecs.srcAmtWithFees = srcAmtWithFees;
        tradeSpecs.cut = srcAmtWithFees.sub(srcAmt);
        tradeSpecs.ethQty = getToken(
            msg.sender,
            src,
            srcAmt,
            srcAmtWithFees
        );
        tradeSpecs.destAmt = kyberFunctions.trade.value(tradeSpecs.ethQty)(
            src,
            srcAmt,
            dest,
            msg.sender,
            maxDestAmt,
            minConversionRate,
            getAddress("admin")
        );

        // factoring maxDestAmt situation
        if (src == eth && address(this).balance > tradeSpecs.cut) {
            msg.sender.transfer(address(this).balance.sub(tradeSpecs.cut));
        } else if (src != eth) {
            IERC20 srcTkn = IERC20(src);
            uint srcBal = srcTkn.balanceOf(address(this));
            if (srcBal > tradeSpecs.cut) {
                srcTkn.transfer(msg.sender, srcBal.sub(tradeSpecs.cut));
            }
        }

        emit KyberTrade(
            src,
            srcAmt,
            dest,
            destAmt,
            msg.sender,
            minConversionRate,
            getAddress("admin"),
            tradeSpecs.cut,
            partner
        );

    }

    function getToken(
        address trader,
        address src,
        uint srcAmt,
        uint srcAmtWithFees
    ) internal returns (uint ethQty)
    {
        if (src == eth) {
            require(msg.value == srcAmt, "Invalid Operation");
            ethQty = srcAmt;
        } else {
            IERC20 tokenFunctions = IERC20(src);
            tokenFunctions.transferFrom(trader, address(this), srcAmtWithFees);
        }
    }

}


contract InstaKyber is Trade {

    event ERC20Collected(address addr, uint amount);
    event ETHCollected(uint amount);

    constructor(address rAddr) public {
        addressRegistry = rAddr;
    }

    function () public payable {}

    function collectERC20(address tknAddr, uint amount) public onlyAdmin {
        IERC20 tkn = IERC20(tknAddr);
        tkn.transfer(msg.sender, amount);
        emit ERC20Collected(tknAddr, amount);
    }

    function collectETH(uint amount) public onlyAdmin {
        msg.sender.transfer(amount);
        emit ETHCollected(amount);
    }

}