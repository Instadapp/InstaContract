// Global Freeze Variable
// withdraw store the 0.5% on the contract itself and can be withdrawn by admin addresses
// after sometime of inactivity, admin have power to change the ownership of the wealth. What say?
// still didn't factor 18 decimal thing on Kyber

pragma solidity ^0.4.24;

interface AddressRegistry {
    function getAddr(string addrName) external returns(address);
}

interface token {
    function transfer(address receiver, uint amount) external returns(bool);
}

interface MoatAsset {
    function getBalance(address assetHolder, address tokenAddr) external view returns (uint256 balance);
    function transferAssets(
        address tokenAddress,
        uint amount,
        address sendTo,
        address target
    ) external;
    function updateBalance(
        address tokenAddress,
        uint amount,
        bool credit,
        address user
    ) external;
}

interface MoatKyber {
    function executeTrade(
        uint weiAmt,
        address src,
        address dest,
        uint srcAmt,
        uint slipRate,
        address walletId
    ) external returns (uint);
}

interface MoatMaker {
    function getLoan(
        address borrower,
        uint lockETH,
        uint loanDAI
    ) external returns (uint, address);
}


contract Registry {

    address public registryAddress;
    modifier onlyAdmin() {
        require(
            msg.sender == getAddress("admin"),
            "Permission Denied"
        );
        _;
    }

    function getAddress(string name) internal view returns(address addr) {
        AddressRegistry aRegistry = AddressRegistry(registryAddress);
        addr = aRegistry.getAddr(name);
        require(addr != address(0), "Invalid Address");
    }
 
}


contract Protocols is Registry {

    event KyberExecute(
        address trader,
        address src,
        address dest,
        uint srcAmt,
        uint destAmt,
        uint slipRate,
        uint fees
    );

    event MakerLoan(
        address borrower,
        uint lockETH,
        uint loanDAI,
        uint feeDeduct
    );

    address eth = 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee;
    uint public fees;
    bool public feesBool;

    function getFees() public view returns(uint, bool) {
        return (fees, feesBool);
    }
    
    function kyberTrade(
        address src,
        address dest,
        uint srcAmt,
        uint slipRate
    ) public payable 
    {
        MoatAsset initMA = MoatAsset(getAddress("asset"));
        
        uint ethVal;
        if (src == eth) {
            ethVal = srcAmt;
        }

        if (msg.value > 0 && msg.value == srcAmt) {
            getAddress("moatkyber").transfer(srcAmt);
        } else {
            initMA.transferAssets(
                src,
                srcAmt,
                getAddress("moatkyber"),
                msg.sender
            );
        }

        // initiate kyber trade
        MoatKyber kybermoat = MoatKyber(getAddress("moatkyber"));
        uint destAmt = kybermoat.executeTrade(
            ethVal,
            src,
            dest,
            srcAmt,
            slipRate,
            getAddress("admin")
        );

        uint feeCut;
        uint modifiedDestAmt = destAmt;
        if (feesBool) {
            feeCut = destAmt/fees;
            modifiedDestAmt = destAmt - feeCut;
        }

        if (dest == eth) {
            getAddress("asset").transfer(modifiedDestAmt);
        } else {
            token tokenFunctions = token(dest);
            tokenFunctions.transfer(getAddress("asset"), destAmt);
        }

        initMA.updateBalance(
            src,
            srcAmt,
            false,
            msg.sender
        );

        initMA.updateBalance(
            dest,
            modifiedDestAmt,
            true,
            msg.sender
        );

        emit KyberExecute(
            msg.sender,
            src,
            dest,
            srcAmt,
            destAmt,
            slipRate,
            feeCut
        );
    }

    function makerBorrow(
        uint lockETH,
        uint loanDAI
    ) public payable
    {

        MoatAsset initMA = MoatAsset(getAddress("asset"));

        if (msg.value > 0) {
            require(lockETH == msg.value, "Possibility of glitch in the Tx");
            getAddress("moatmaker").transfer(msg.value);
        } else {
            initMA.transferAssets(
                eth,
                lockETH,
                getAddress("moatmaker"),
                msg.sender
            );
            initMA.updateBalance(
                eth,
                lockETH,
                false,
                msg.sender
            );
        }

        MoatMaker makermoat = MoatMaker(getAddress("moatmaker"));
        uint daiMinted;
        address daiAddr;
        (daiMinted, daiAddr) = makermoat.getLoan(
            msg.sender,
            lockETH,
            loanDAI
        );

        uint modifiedLoanDAI;
        uint feeDeduct;
        if (loanDAI > 0) {
            if (feesBool) {
                feeDeduct = loanDAI/fees;
                modifiedLoanDAI = loanDAI - feeDeduct;
            }
            token tokenFunctions = token(daiAddr);
            tokenFunctions.transfer(getAddress("asset"), modifiedLoanDAI);
            initMA.updateBalance(
                daiAddr,
                modifiedLoanDAI,
                true,
                msg.sender
            );
        }

        emit MakerLoan(msg.sender, lockETH, loanDAI, feeDeduct);
    }

}


contract MoatResolver is Protocols {

    function () public payable {}

    constructor(address rAddr, uint cut) public { // 200 means 0.5% 
        registryAddress = rAddr;
        fees = cut;
    }

    function collectFees(address tokenAddress, uint amount) public onlyAdmin {
        if (tokenAddress == eth) {
            msg.sender.transfer(amount);
        } else {
            token tokenFunctions = token(tokenAddress);
            tokenFunctions.transfer(msg.sender, amount);
        }
    }

    function enableFees() public onlyAdmin {
        feesBool = true;
    }

    function disableFees() public onlyAdmin {
        feesBool = false;
    }

}