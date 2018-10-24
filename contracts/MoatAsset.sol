// Allow ERC20 deposits
// withdraw the extra assets other than global balance (in case anyone donated for free) and then no need for seperate brokerage calculation

pragma solidity ^0.4.24;

interface AddressRegistry {
    function getAddr(string AddrName) external returns(address);
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
    function getAddress(string AddressName) internal view returns(address) {
        AddressRegistry aRegistry = AddressRegistry(registryAddress);
        address realAddress = aRegistry.getAddr(AddressName);
        require(realAddress != address(0), "Invalid Address");
        return realAddress;
    }
}

contract AllowedResolver is Registry {

    // Contract Address >> Asset Owner Address >> Bool
    mapping(address => mapping(address => bool)) allowed;
    bool public ACEnabled;
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
        ACEnabled = true;
    }
    function disableAC() public onlyAdmin {
        ACEnabled = false;
    }

}

contract MoatAsset is AllowedResolver {

    // AssetOwner >> TokenAddress >> Balance (as per respective decimals)
    mapping(address => mapping(address => uint)) Balances;
    address ETH = 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee;

    function getBalance(
        address AssetHolder,
        address Token
    ) public view returns (uint256 balance) {
        return Balances[AssetHolder][Token];
    }

    // received ether directly from protocols like Kyber Network
    // emit an event atleast
    function () public payable {}

    function Deposit() public payable {
        Balances[msg.sender][ETH] += msg.value;
    }

    function Withdraw(
        address addr,
        uint amt
    ) public {
        require(Balances[msg.sender][addr] >= amt, "Insufficient Balance");
        Balances[msg.sender][addr] -= amt;
        if (addr == ETH) {
            msg.sender.transfer(amt);
        } else {
            token tokenFunctions = token(addr);
            tokenFunctions.transfer(msg.sender, amt);
        }
    }

    function UpdateBalance(
        address tokenAddr,
        uint amt,
        bool add,
        address target
    ) public onlyAllowedResolver {
        if (add) {
            Balances[target][tokenAddr] += amt;
        } else {
            Balances[target][tokenAddr] -= amt;
        }
    }

    function TransferAssets(
        address tokenAddress,
        uint amount,
        address sendTo
    ) public onlyAllowedResolver {
        if (tokenAddress == ETH) {
            sendTo.transfer(amount);
        } else {
            token tokenFunctions = token(tokenAddress);
            tokenFunctions.transfer(sendTo, amount);
        }
    }

    constructor(address rAddr) public {
        registryAddress = rAddr;
        enableAC();
    }

}