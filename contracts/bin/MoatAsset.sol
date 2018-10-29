// // withdraw the extra assets other than global balance (in case anyone donated for free) and then no need for seperate brokerage calculation
// // IMPORTANT CHECK - decimals() - how the balance of tokens with less than 18 decimals are stored. Factor it.
// // update the balance along with "transferAssets" functions and also check the for onlyAllowedResolver
// // transfer assets to different address (create 2 different mappings) - 48 hour time to transfer all - send email for this

// pragma solidity ^0.4.24;

// import "openzeppelin-solidity/contracts/math/SafeMath.sol";
// import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

// interface AddressRegistry {
//     function getAddr(string name) external view returns(address);
//     function isApprovedResolver(address user) external view returns(bool);
// }


// contract Registry {

//     address public registryAddress;
//     AddressRegistry addrReg = AddressRegistry(registryAddress);

//     modifier onlyAllowedResolver(address user) {
//         require(
//             addrReg.isApprovedResolver(user),
//             "Permission Denied"
//         );
//         _;
//     }

//     function getAddress(string name) internal view returns(address addr) {
//         addr = addrReg.getAddr(name);
//         require(addr != address(0), "Invalid Address");
//     }

// }


// contract AssetDB is Registry {

//     using SafeMath for uint;
//     using SafeMath for uint256;

//     mapping(address => mapping(address => uint)) balances;
//     address eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

//     function getBalance(
//         address assetHolder,
//         address tokenAddr
//     ) public view returns (uint256 balance)
//     {
//         balance = balances[assetHolder][tokenAddr];
//     }

//     function deposit(address tknAddr, uint amount) public payable {
//         if (msg.value > 0) {
//             balances[msg.sender][eth] = balances[msg.sender][eth].add(msg.value);
//         } else {
//             IERC20 tokenFunctions = IERC20(tknAddr);
//             tokenFunctions.transferFrom(msg.sender, address(this), amount);
//             balances[msg.sender][tknAddr] = balances[msg.sender][tknAddr].add(amount);
//         }
//     }

//     function withdraw(address tknAddr, uint amount) public {
//         require(balances[msg.sender][tknAddr] >= amount, "Insufficient Balance");
//         balances[msg.sender][tknAddr] = balances[msg.sender][tknAddr].sub(amount);
//         if (tknAddr == eth) {
//             msg.sender.transfer(amount);
//         } else {
//             IERC20 tokenFunctions = IERC20(tknAddr);
//             tokenFunctions.transfer(msg.sender, amount);
//         }
//     }

//     function updateBalance(
//         address tokenAddr,
//         uint amount,
//         bool credit,
//         address user
//     ) public onlyAllowedResolver(user)
//     {
//         if (credit) {
//             balances[user][tokenAddr] = balances[user][tokenAddr].add(amount);
//         } else {
//             balances[user][tokenAddr] = balances[user][tokenAddr].sub(amount);
//         }
//     }

//     function transferAssets(
//         address tokenAddress,
//         uint amount,
//         address sendTo,
//         address user
//     ) public onlyAllowedResolver(user)
//     {
//         if (tokenAddress == eth) {
//             sendTo.transfer(amount);
//         } else {
//             IERC20 tokenFunctions = IERC20(tokenAddress);
//             tokenFunctions.transfer(sendTo, amount);
//         }
//         balances[user][tokenAddress] = balances[user][tokenAddress].sub(amount);
//     }

// }


// contract MoatAsset is AssetDB {

//     constructor(address rAddr) public {
//         registryAddress = rAddr;
//     }

//     function () public payable {}

// }
