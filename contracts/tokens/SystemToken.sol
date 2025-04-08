// SDPX-License-Identifier: MIT

pragma solidity 0.8.29;

import "../bundles/ERC20Bundle.sol";

contract SystemToken is ERC20 {
    constructor(address[] memory _daoMembers) ERC20("Professional", "PROFI") {
        uint256 initSupply = 100_000 * 10**decimals();
        uint256 initBalancePerMember = initSupply / _daoMembers.length;
        
        // Минт 100 000 токенов владельцу контракта
        _mint(msg.sender, initSupply);

        // Разделение токенов в равном количестве между участниками DAO
        for(uint256 i = 0; i < _daoMembers.length; i++) {
            _transfer(msg.sender, _daoMembers[i], initBalancePerMember);
        }
    }

    function decimals() public pure override returns(uint8) {
        return 12;
    }

    function transferFrom(address _from, address _to, uint256 _amount) public override returns(bool) {
        _transfer(_from, _to, _amount);
        return true;
    }
}