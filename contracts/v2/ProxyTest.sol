pragma solidity ^0.4.23;


contract ProxyTest {

    function sendETH() public payable {
        address(msg.sender).transfer(msg.value);
    }

}