// SPDX-License-Identifier: MIT

pragma solidity ^0.8.8;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "./interfaces/IERC20Mintable.sol";
import "./interfaces/ITokensVesting.sol";

contract TokensVesting is AccessControlEnumerable, ITokensVesting {
    using EnumerableSet for EnumerableSet.UintSet;

    bytes32 public constant MAINTAINER_ROLE = keccak256("MAINTAINER_ROLE");
    bytes32 public constant DEFI_ROLE = keccak256("DEFI_ROLE");
    bytes32 public constant GAME_INCENTIVES_ROLE =
        keccak256("GAME_INCENTIVES_ROLE");

    IERC20Mintable public immutable token;

    VestingInfo[] private _beneficiaries;
    mapping(address => EnumerableSet.UintSet)
        private _beneficiaryAddressIndexes;
    mapping(bytes32 => EnumerableSet.UintSet) private _beneficiaryRoleIndexes;
    EnumerableSet.UintSet private _revokedBeneficiaryIndexes;

    constructor(address token_) {
        require(
            token_ != address(0),
            "TokensVesting::constructor: _token is the zero address!"
        );
        token = IERC20Mintable(token_);

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MAINTAINER_ROLE, _msgSender());
    }

    function _addBeneficiary(
        address beneficiary_,
        bytes32 role_,
        uint256 genesisTimestamp_,
        uint256 totalAmount_,
        uint256 tgeAmount_,
        uint256 finalAmount_,
        uint256 basis_,
        uint256 cliff_,
        uint256 duration_,
        uint8 participant_
    ) private returns (uint256 _index) {
        require(
            beneficiary_ != address(0) || role_ != 0,
            "TokensVesting: must specify beneficiary or role"
        );

        if (beneficiary_ != address(0)) {
            VestingInfo storage _info = _beneficiaries.push();
            _info.beneficiary = beneficiary_;
            _info.genesisTimestamp = genesisTimestamp_;
            _info.totalAmount = totalAmount_;
            _info.tgeAmount = tgeAmount_;
            _info.finalAmount = finalAmount_;
            _info.basis = basis_;
            _info.cliff = cliff_;
            _info.duration = duration_;
            _info.participant = Participant(participant_);

            _index = _beneficiaries.length - 1;

            require(
                _beneficiaryAddressIndexes[beneficiary_].add(_index),
                "TokensVesting: Duplicated index"
            );

            emit BeneficiaryAddressAdded(
                beneficiary_,
                totalAmount_,
                participant_
            );
        } else {
            VestingInfo storage _info = _beneficiaries.push();
            _info.role = role_;
            _info.genesisTimestamp = genesisTimestamp_;
            _info.totalAmount = totalAmount_;
            _info.tgeAmount = tgeAmount_;
            _info.finalAmount = finalAmount_;
            _info.basis = basis_;
            _info.cliff = cliff_;
            _info.duration = duration_;
            _info.participant = Participant(participant_);

            _index = _beneficiaries.length - 1;

            require(
                _beneficiaryRoleIndexes[role_].add(_index),
                "TokensVesting: Duplicated index"
            );

            emit BeneficiaryRoleAdded(role_, totalAmount_, participant_);
        }
    }

    function _vestedAmount(uint256 index_) private view returns (uint256) {
        VestingInfo storage _info = _beneficiaries[index_];

        if (block.timestamp < _info.genesisTimestamp) {
            return 0;
        }

        uint256 _elapsedTime = block.timestamp - _info.genesisTimestamp;
        if (_elapsedTime < _info.cliff) {
            return _info.tgeAmount;
        }

        if (_elapsedTime >= _info.cliff + _info.duration) {
            return _info.totalAmount;
        }

        uint256 _releaseMilestones = (_elapsedTime - _info.cliff) /
            _info.basis +
            1;
        uint256 _totalReleaseMilestones = (_info.duration + _info.basis - 1) /
            _info.basis +
            1;

        if (_releaseMilestones >= _totalReleaseMilestones) {
            return _info.totalAmount;
        }

        // _totalReleaseMilestones > 1
        uint256 _linearVestingAmount = _info.totalAmount -
            _info.tgeAmount -
            _info.finalAmount;
        return
            (_linearVestingAmount / (_totalReleaseMilestones - 1)) *
            _releaseMilestones +
            _info.tgeAmount;
    }

    function _releasableAmount(uint256 index_) private view returns (uint256) {
        if (_revokedBeneficiaryIndexes.contains(index_)) {
            return 0;
        }

        VestingInfo storage _info = _beneficiaries[index_];
        return _vestedAmount(index_) - _info.releasedAmount;
    }

    function _releaseAll() private {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            VestingInfo storage _info = _beneficiaries[_index];
            if (_info.beneficiary != address(0)) {
                uint256 _unreleaseAmount = _releasableAmount(_index);
                if (_unreleaseAmount > 0) {
                    _info.releasedAmount =
                        _info.releasedAmount +
                        _unreleaseAmount;
                    token.mint(_info.beneficiary, _unreleaseAmount);
                    emit TokensReleased(_info.beneficiary, _unreleaseAmount);
                }
            }
        }
    }

    function _releaseParticipant(uint8 participant_) private {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            VestingInfo storage _info = _beneficiaries[_index];
            if (
                _info.beneficiary != address(0) &&
                uint8(_info.participant) == participant_
            ) {
                uint256 _unreleaseAmount = _releasableAmount(_index);
                if (_unreleaseAmount > 0) {
                    _info.releasedAmount =
                        _info.releasedAmount +
                        _unreleaseAmount;
                    token.mint(_info.beneficiary, _unreleaseAmount);
                    emit TokensReleased(_info.beneficiary, _unreleaseAmount);
                }
            }
        }
    }

    function _release(uint256 index_, address recipient_) private {
        VestingInfo storage _info = _beneficiaries[index_];
        uint256 _unreleaseAmount = _releasableAmount(index_);
        if (_unreleaseAmount > 0) {
            _info.releasedAmount = _info.releasedAmount + _unreleaseAmount;
            token.mint(recipient_, _unreleaseAmount);
            emit TokensReleased(recipient_, _unreleaseAmount);
        }
    }

    /**
     * Only call this function when releasableAmountOfRole >= amount_
     */
    function _releaseTokensOfRole(
        bytes32 role_,
        uint256 amount_,
        address reicipient_
    ) private {
        uint256 _amountToRelease = amount_;

        for (
            uint256 _index = 0;
            _index < _beneficiaryRoleIndexes[role_].length();
            _index++
        ) {
            uint256 _beneficiaryIndex = _beneficiaryRoleIndexes[role_].at(
                _index
            );
            VestingInfo storage _info = _beneficiaries[_beneficiaryIndex];
            uint256 _unreleaseAmount = _releasableAmount(_beneficiaryIndex);

            if (_unreleaseAmount > 0) {
                if (_unreleaseAmount >= _amountToRelease) {
                    _info.releasedAmount =
                        _info.releasedAmount +
                        _amountToRelease;
                    break;
                } else {
                    _info.releasedAmount =
                        _info.releasedAmount +
                        _unreleaseAmount;
                    _amountToRelease -= _unreleaseAmount;
                }
            }
        }

        token.mint(reicipient_, amount_);
        emit TokensReleased(_msgSender(), amount_);
    }

    function _revoke(uint256 index_) private {
        bool _success = _revokedBeneficiaryIndexes.add(index_);
        if (_success) {
            emit BeneficiaryRevoked(index_);
        }
    }

    function addBeneficiary(
        address beneficiary_,
        bytes32 role_,
        uint256 genesisTimestamp_,
        uint256 totalAmount_,
        uint256 tgeAmount_,
        uint256 finalAmount_,
        uint256 basis_,
        uint256 cliff_,
        uint256 duration_,
        uint8 participant_
    ) external onlyRole(MAINTAINER_ROLE) returns (uint256) {
        require(genesisTimestamp_ > 0, "TokensVesting: genesisTimestamp_ is 0");
        require(
            totalAmount_ >= tgeAmount_ + finalAmount_,
            "TokensVesting: bad args"
        );
        require(basis_ > 0, "TokensVesting: basis_ must be greater than 0");
        require(
            genesisTimestamp_ + cliff_ + duration_ <= type(uint256).max,
            "TokensVesting: out of uint256 range"
        );
        require(
            Participant(participant_) > Participant.Unknown &&
                Participant(participant_) < Participant.OutOfRange,
            "TokensVesting: participant_ out of range"
        );

        return
            _addBeneficiary(
                beneficiary_,
                role_,
                genesisTimestamp_,
                totalAmount_,
                tgeAmount_,
                finalAmount_,
                basis_,
                cliff_,
                duration_,
                participant_
            );
    }

    function releaseAll() external onlyRole(MAINTAINER_ROLE) {
        _releaseAll();
    }

    function releaseParticipant(uint8 participant_)
        external
        onlyRole(MAINTAINER_ROLE)
    {
        _releaseParticipant(participant_);
    }

    function releaseMyTokens() external {
        require(
            _beneficiaryAddressIndexes[_msgSender()].length() > 0,
            "TokensVesting: sender is not in vesting plan"
        );

        for (
            uint256 _index = 0;
            _index < _beneficiaryAddressIndexes[_msgSender()].length();
            _index++
        ) {
            uint256 _beneficiaryIndex = _beneficiaryAddressIndexes[_msgSender()]
                .at(_index);
            VestingInfo storage _info = _beneficiaries[_beneficiaryIndex];

            uint256 _unreleaseAmount = _releasableAmount(_beneficiaryIndex);
            if (_unreleaseAmount > 0) {
                _info.releasedAmount = _info.releasedAmount + _unreleaseAmount;
                token.mint(_msgSender(), _unreleaseAmount);
                emit TokensReleased(_msgSender(), _unreleaseAmount);
            }
        }
    }

    function releaseTokensOfRole(bytes32 role_, uint256 amount_) external {
        require(
            hasRole(role_, _msgSender()),
            "TokensVesting: unauthorized sender"
        );
        require(
            releasableAmountOfRole(role_) > 0,
            "TokensVesting: no tokens are due"
        );
        require(
            releasableAmountOfRole(role_) >= amount_,
            "TokensVesting: insufficient amount"
        );

        _releaseTokensOfRole(role_, amount_, _msgSender());
    }

    function release(uint256 index_) external {
        require(
            _beneficiaries[index_].beneficiary != address(0),
            "TokensVesting: bad index_"
        );
        require(
            hasRole(MAINTAINER_ROLE, _msgSender()) ||
                _beneficiaries[index_].beneficiary == _msgSender(),
            "TokensVesting: unauthorized sender"
        );

        _release(index_, _beneficiaries[index_].beneficiary);
    }

    function revokeTokensOfParticipant(uint8 participant_)
        external
        onlyRole(MAINTAINER_ROLE)
    {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            if (uint8(_beneficiaries[_index].participant) == participant_) {
                _revoke(_index);
            }
        }
    }

    function revokeTokensOfAddress(address beneficiary_)
        external
        onlyRole(MAINTAINER_ROLE)
    {
        for (
            uint256 _index = 0;
            _index < _beneficiaryAddressIndexes[beneficiary_].length();
            _index++
        ) {
            uint256 _addressIndex = _beneficiaryAddressIndexes[beneficiary_].at(
                _index
            );
            _revoke(_addressIndex);
        }
    }

    function revokeTokensOfRole(bytes32 role_)
        external
        onlyRole(MAINTAINER_ROLE)
    {
        for (
            uint256 _index = 0;
            _index < _beneficiaryRoleIndexes[role_].length();
            _index++
        ) {
            uint256 _roleIndex = _beneficiaryRoleIndexes[role_].at(_index);
            _revoke(_roleIndex);
        }
    }

    function revoke(uint256 index_) external onlyRole(MAINTAINER_ROLE) {
        require(
            _revokedBeneficiaryIndexes.add(index_),
            "TokensVesting: already revoked"
        );
        emit BeneficiaryRevoked(index_);
    }

    function releasableAmount() public view returns (uint256 _amount) {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            _amount += _releasableAmount(_index);
        }
    }

    function releasableAmountOfParticipant(uint8 participant_)
        public
        view
        returns (uint256 _amount)
    {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            if (uint8(_beneficiaries[_index].participant) == participant_) {
                _amount += _releasableAmount(_index);
            }
        }
    }

    function releasableAmountOfAddress(address beneficiary_)
        public
        view
        returns (uint256 _amount)
    {
        for (
            uint256 _index = 0;
            _index < _beneficiaryAddressIndexes[beneficiary_].length();
            _index++
        ) {
            uint256 _addressIndex = _beneficiaryAddressIndexes[beneficiary_].at(
                _index
            );
            _amount += _releasableAmount(_addressIndex);
        }
    }

    function releasableAmountOfRole(bytes32 role_)
        public
        view
        returns (uint256 _amount)
    {
        for (
            uint256 _index = 0;
            _index < _beneficiaryRoleIndexes[role_].length();
            _index++
        ) {
            uint256 _roleIndex = _beneficiaryRoleIndexes[role_].at(_index);
            _amount += _releasableAmount(_roleIndex);
        }
    }

    function releasableAmountAt(uint256 index_)
        public
        view
        returns (uint256 _amount)
    {
        return _releasableAmount(index_);
    }

    function totalAmount() public view returns (uint256 _amount) {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            _amount += _beneficiaries[_index].totalAmount;
        }
    }

    function totalAmountOfParticipant(uint8 participant_)
        public
        view
        returns (uint256 _amount)
    {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            if (uint8(_beneficiaries[_index].participant) == participant_) {
                _amount += _beneficiaries[_index].totalAmount;
            }
        }
    }

    function totalAmountOfAddress(address beneficiary_)
        public
        view
        returns (uint256 _amount)
    {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            if (_beneficiaries[_index].beneficiary == beneficiary_) {
                _amount += _beneficiaries[_index].totalAmount;
            }
        }
    }

    function totalAmountOfRole(bytes32 role_)
        public
        view
        returns (uint256 _amount)
    {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            if (_beneficiaries[_index].role == role_) {
                _amount += _beneficiaries[_index].totalAmount;
            }
        }
    }

    function totalAmountAt(uint256 index_) public view returns (uint256) {
        return _beneficiaries[index_].totalAmount;
    }

    function releasedAmount() public view returns (uint256 _amount) {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            _amount += _beneficiaries[_index].releasedAmount;
        }
    }

    function releasedAmountOfParticipant(uint8 participant_)
        public
        view
        returns (uint256 _amount)
    {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            if (uint8(_beneficiaries[_index].participant) == participant_) {
                _amount += _beneficiaries[_index].releasedAmount;
            }
        }
    }

    function releasedAmountOfAddress(address beneficiary_)
        public
        view
        returns (uint256 _amount)
    {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            if (_beneficiaries[_index].beneficiary == beneficiary_) {
                _amount += _beneficiaries[_index].releasedAmount;
            }
        }
    }

    function releasedAmountOfRole(bytes32 role_)
        public
        view
        returns (uint256 _amount)
    {
        for (uint256 _index = 0; _index < _beneficiaries.length; _index++) {
            if (_beneficiaries[_index].role == role_) {
                _amount += _beneficiaries[_index].releasedAmount;
            }
        }
    }

    function releasedAmountAt(uint256 index_) public view returns (uint256) {
        return _beneficiaries[index_].releasedAmount;
    }

    function vestingInfoAt(uint256 index_)
        public
        view
        returns (VestingInfo memory)
    {
        return _beneficiaries[index_];
    }

    function indexesOfBeneficiary(address beneficiary_)
        public
        view
        returns (uint256[] memory)
    {
        return _beneficiaryAddressIndexes[beneficiary_].values();
    }

    function indexesOfRole(bytes32 role_)
        public
        view
        returns (uint256[] memory)
    {
        return _beneficiaryRoleIndexes[role_].values();
    }

    function revokedIndexes() public view returns (uint256[] memory) {
        return _revokedBeneficiaryIndexes.values();
    }
}
