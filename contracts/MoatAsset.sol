// Allow ERC20 deposits
// withdraw the extra assets other than global balance (in case anyone donated for free) and then no need for seperate brokerage calculation
// how the balance of tokens with less than 18 decimals are stored
// update the balance along with "transferAssets" functions and also check the for onlyAllowedResolver

pragma solidity ^0.4.24;

interface AddressRegistry {
    function getAddr(string name) external returns(address);
    function isApprovedResolver(address user) external returns(bool);
}

interface token {
    function approve(address spender, uint256 value) external returns (bool);
    function transfer(address receiver, uint amount) external returns (bool);
}


contract Registry {

    address public registryAddress;
    AddressRegistry aRegistry = AddressRegistry(registryAddress);

    modifier onlyAdmin() {
        require(
            msg.sender == getAddress("admin"),
            "Permission Denied"
        );
        _;
    }

    modifier onlyAllowedResolver(address user) {
        require(
            aRegistry.isApprovedResolver(user),
            "Permission Denied"
        );
        _;
    }

    function getAddress(string name) internal view returns(address addr) {
        addr = aRegistry.getAddr(name);
        require(addr != address(0), "Invalid Address");
    }
 
}


contract AssetDB is Registry {

    // AssetOwner >> TokenAddress >> Balance (as per respective decimals)
    mapping(address => mapping(address => uint)) balances;
    address eth = 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee;

    function getBalance(
        address assetHolder,
        address token
    ) public view returns (uint256 balance)
    {
        balance = balances[assetHolder][token];
    }

    function deposit() public payable {
        balances[msg.sender][eth] += msg.value;
    }

    function withdraw(address addr, uint amt) public {
        require(balances[msg.sender][addr] >= amt, "Insufficient Balance");
        balances[msg.sender][addr] -= amt;
        if (addr == eth) {
            msg.sender.transfer(amt);
        } else {
            token tokenFunctions = token(addr);
            tokenFunctions.transfer(msg.sender, amt);
        }
    }

    function updateBalance(
        address tokenAddr,
        uint amt,
        bool add,
        address target
    ) public onlyAllowedResolver(target)
    {
        if (add) {
            balances[target][tokenAddr] += amt;
        } else {
            balances[target][tokenAddr] -= amt;
        }
    }

    // function transferAssets(
    //     address tokenAddress,
    //     uint amount,
    //     address sendTo
    // ) public onlyAllowedResolver 
    // {
    //     if (tokenAddress == eth) {
    //         sendTo.transfer(amount);
    //     } else {
    //         token tokenFunctions = token(tokenAddress);
    //         tokenFunctions.transfer(sendTo, amount);
    //     }
    // }

}


contract MoatAsset is AssetDB {

    constructor(address rAddr) public {
        registryAddress = rAddr;
    }

    // received ether directly from protocols like Kyber Network
    // emit an event atleast
    function () public payable {}

}