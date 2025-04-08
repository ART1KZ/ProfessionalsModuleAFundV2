// SDPX-License-Identifier: MIT

pragma solidity 0.8.29;

import "../bundles/ERC20Bundle.sol";

contract SystemToken is ERC20 {
    constructor() ERC20("RTKCoin", "RTK") {
        uint256 initSupply = 20_000_000;

        _mint(msg.sender, initSupply);
    }

    function decimals() public pure override returns(uint8) {
        return 12;
    }

    function transferFrom(address _from, address _to, uint256 _amount) public override returns(bool) {
        _transfer(_from, _to, _amount);
        return true;
    }

    function price() public pure returns(uint256) {
        return 1 ether;
    }
}