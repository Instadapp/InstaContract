// withdraw the extra assets other than global balance (in case anyone donated for free) and then no need for seperate brokerage calculation
// IMPORTANT CHECK - decimals() - how the balance of tokens with less than 18 decimals are stored. Factor it.
// update the balance along with "transferAssets" functions and also check the for onlyAllowedResolver
// transfer assets to different address (create 2 different mappings) - 48 hour time to transfer all - send email for this

pragma solidity ^0.4.24;

interface AddressRegistry {
    function getAddr(string name) external returns(address);
    function isApprovedResolver(address user) external returns(bool);
}

interface token {
    function approve(address spender, uint256 value) external returns (bool);
    function transfer(address receiver, uint amount) external returns (bool);
    function transferFrom(address from, address to, uint amount) external returns (bool);
}


contract Registry {

    address public registryAddress;
    AddressRegistry aRegistry = AddressRegistry(registryAddress);

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

    mapping(address => mapping(address => uint)) balances;
    address eth = 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee;

    function getBalance(
        address assetHolder,
        address tokenAddr
    ) public view returns (uint256 balance)
    {
        balance = balances[assetHolder][tokenAddr];
    }

    function deposit(address tknAddr, uint amount) public payable {
        if (msg.value > 0) {
            balances[msg.sender][eth] += msg.value;
        } else {
            token tokenFunctions = token(tknAddr);
            tokenFunctions.transferFrom(msg.sender, address(this), amount);
            balances[msg.sender][tknAddr] += amount;
        }
    }

    function withdraw(address tknAddr, uint amount) public {
        require(balances[msg.sender][tknAddr] >= amount, "Insufficient Balance");
        balances[msg.sender][tknAddr] -= amount;
        if (tknAddr == eth) {
            msg.sender.transfer(amount);
        } else {
            token tokenFunctions = token(tknAddr);
            tokenFunctions.transfer(msg.sender, amount);
        }
    }

    function updateBalance(
        address tokenAddr,
        uint amount,
        bool credit,
        address user
    ) public onlyAllowedResolver(user)
    {
        if (credit) {
            balances[user][tokenAddr] += amount;
        } else {
            balances[user][tokenAddr] -= amount;
        }
    }

    function transferAssets(
        address tokenAddress,
        uint amount,
        address sendTo,
        address user
    ) public onlyAllowedResolver(user)
    {
        if (tokenAddress == eth) {
            sendTo.transfer(amount);
        } else {
            token tokenFunctions = token(tokenAddress);
            tokenFunctions.transfer(sendTo, amount);
        }
        balances[user][tokenAddress] -= amount;
    }

}


contract MoatAsset is AssetDB {

    constructor(address rAddr) public {
        registryAddress = rAddr;
    }

    function () public payable {}

}