// Global Freeze Variable
// withdraw store the 0.5% on the contract itself and can be withdrawn by admin addresses
// after sometime of inactivity, admin have power to change the ownership of the wealth. What say?

pragma solidity ^0.4.24;

interface AddressRegistry {
    function getAddr(string AddrName) external returns(address);
}

interface MoatAsset {
    function getBalance(address assetHolder, address tokenAddr) external view returns (uint256 balance);
    function transferAssets(address tokenAddress, uint amount, address sendTo, address target) external;
    function updateBalance(address tokenAddress, uint amount, bool credit, address user) external;
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


contract Registry {
    address public RegistryAddress;
    modifier onlyAdmin() {
        require(
            msg.sender == getAddress("admin"),
            "Permission Denied"
        );
        _;
    }
    function getAddress(string AddressName) internal view returns(address) {
        AddressRegistry aRegistry = AddressRegistry(RegistryAddress);
        address realAddress = aRegistry.getAddr(AddressName);
        require(realAddress != address(0), "Invalid Address");
        return realAddress;
    }
}


contract Protocols is Registry {

    address eth = 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee;
    uint public fees;
    bool public feesBool;

    

    event KyberExecute(address src, address dest, uint srcAmt, uint destAmt, uint slipRate, uint fees);
    
    function kyberTrade(
        uint weiAmt,
        address src,
        address dest,
        uint srcAmt,
        uint slipRate
    ) public payable {

        MoatAsset MAFunctions = MoatAsset(getAddress("asset"));
        uint ethVal;

        if (msg.value > 0) {
            ethVal = msg.value;
            getAddress("moatkyber").transfer(msg.value);
        } else {
            ethVal = weiAmt;
            MAFunctions.transferAssets(src, srcAmt, getAddress("moatkyber"), msg.sender);
        }

        // get assets from MoatAsset or user individual wallet
        // send that asset to MoatKyber

        // initiate kyber trade
        MoatKyber kmoat = MoatKyber(getAddress("moatkyber"));
        uint destAmt = kmoat.executeTrade(
            ethVal,
            src,
            dest,
            srcAmt,
            slipRate,
            getAddress("admin")
        );

        MAFunctions.updateBalance(dest, destAmt, true, msg.sender);

        // fees deduction only if the user have ETH balance
        uint assetBal = MAFunctions.getBalance(msg.sender, eth);
        if (assetBal > 0 && feesBool) {
            if (src == eth) { // if selling ETH
                MAFunctions.transferAssets(eth, ethVal/200, address(this), msg.sender);
                emit KyberExecute(src, dest, srcAmt, destAmt, slipRate, ethVal/200);
            } else { // if buying ETH
                MAFunctions.transferAssets(eth, destAmt/200, address(this), msg.sender);
                emit KyberExecute(src, dest, srcAmt, destAmt, slipRate, destAmt/200);
            }
        } else {
            emit KyberExecute(src, dest, srcAmt, destAmt, slipRate, 0);
        }

    }

}


contract MoatResolver is Protocols {

    function () public payable {}

    constructor(address rAddr, uint cut) public { // 200 means 0.5% 
        RegistryAddress = rAddr;
        fees = cut;
    }

}