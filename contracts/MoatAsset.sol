// Allow ERC20 deposits
// withdraw the extra assets other than global balance (in case anyone donated for free) and then no need for seperate brokerage calculation

pragma solidity ^0.4.24;

interface AddressRegistry {
    function getAddr(string name) external returns(address);
}

interface token {
    function approve(address spender, uint256 value) external returns (bool);
    function transfer(address receiver, uint amount) external returns (bool);
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


contract AllowedResolver is Registry {

    // Contract Address >> Asset Owner Address >> Bool
    mapping(address => mapping(address => bool)) allowed;
    bool public enabled;
    modifier onlyAllowedResolver() {
        require(
            allowed[getAddress("resolver")][msg.sender],
            "Permission Denied"
        );
        _;
    }

    // only the contracts allowed for asset owners can withdraw assets and update balance on behalf
    function allowContract() public {
        allowed[getAddress("resolver")][msg.sender] = true;
    }

    function disallowContract() public {
        allowed[getAddress("resolver")][msg.sender] = false;
    }

    // enableAC & disableAC will completely stop the withdrawal of assets on behalf (additional security check)
    function enableAC() public onlyAdmin {
        enabled = true;
    }

    function disableAC() public onlyAdmin {
        enabled = false;
    }

}


contract AssetDB is AllowedResolver {

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
    ) public onlyAllowedResolver 
    {
        if (add) {
            balances[target][tokenAddr] += amt;
        } else {
            balances[target][tokenAddr] -= amt;
        }
    }

    function transferAssets(
        address tokenAddress,
        uint amount,
        address sendTo
    ) public onlyAllowedResolver 
    {
        if (tokenAddress == eth) {
            sendTo.transfer(amount);
        } else {
            token tokenFunctions = token(tokenAddress);
            tokenFunctions.transfer(sendTo, amount);
        }
    }

}


contract MoatAsset is AssetDB {

    constructor(address rAddr) public {
        registryAddress = rAddr;
        enableAC();
    }

    // received ether directly from protocols like Kyber Network
    // emit an event atleast
    function () public payable {}

}