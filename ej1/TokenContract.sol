// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.30;

contract TokenContract {
    address public owner;

    struct Receivers {
        string name;
        uint256 tokens;
    }

    mapping(address => Receivers) public users;

    uint256 public constant TOKEN_PRICE = 5 ether;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        users[owner].tokens = 100; // initial stock
    }

    function double(uint256 _value) public pure returns (uint256) {
        return _value * 2;
    }

    function register(string memory _name) public {
        users[msg.sender].name = _name;
    }

    function giveToken(address _receiver, uint256 _amount) public onlyOwner {
        require(users[owner].tokens >= _amount, "Owner lacks tokens");
        users[owner].tokens -= _amount;
        users[_receiver].tokens += _amount;
    }

    // ---- Buy tokens at 5 ETH each ----
    function buyTokens(uint256 amount) external payable {
        require(amount > 0, "Amount is zero");
        uint256 cost = amount * TOKEN_PRICE;
        require(msg.value == cost, "Incorrect ETH sent");
        require(users[owner].tokens >= amount, "Not enough tokens in stock");

        users[owner].tokens -= amount;
        users[msg.sender].tokens += amount;
    }

    // View ETH accumulated by sales
    function contractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // Owner withdraws ETH
    function withdraw(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient contract balance");
        (bool ok, ) = payable(owner).call{value: amount}("");
        require(ok, "Withdraw failed");
    }

    // Prevent accidental ETH transfers outside buyTokens
    receive() external payable {
        revert("Send ETH via buyTokens");
    }

    fallback() external payable {
        revert("Invalid call");
    }
}
