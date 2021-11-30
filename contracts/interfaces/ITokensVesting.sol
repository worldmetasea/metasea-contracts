// SPDX-License-Identifier: MIT

pragma solidity ^0.8.8;

import "./IERC20Mintable.sol";

interface ITokensVesting {
    enum Participant {
        Unknown,
        Seeding,
        PrivateSale,
        PublicSale,
        Team,
        DeFi,
        Marketing,
        Reserve,
        GameIncentives,
        Liquidity,
        Development,
        OutOfRange
    }

    struct VestingInfo {
        uint256 genesisTimestamp;
        uint256 totalAmount;
        uint256 tgeAmount;
        uint256 finalAmount;
        uint256 basis;
        uint256 cliff;
        uint256 duration;
        uint256 releasedAmount;
        address beneficiary;
        bytes32 role;
        Participant participant;
    }

    event BeneficiaryAddressAdded(
        address indexed beneficiary,
        uint256 amount,
        uint8 participant
    );
    event BeneficiaryRoleAdded(
        bytes32 indexed role,
        uint256 amount,
        uint8 participant
    );
    event BeneficiaryRevoked(uint256 indexed index);
    event TokensReleased(address indexed recipient, uint256 amount);

    function addBeneficiary(
        address beneficiary,
        bytes32 role,
        uint256 genesisTimestamp,
        uint256 totalAmount,
        uint256 tgeAmount,
        uint256 finalAmount,
        uint256 basis,
        uint256 cliff,
        uint256 duration,
        uint8 participant
    ) external returns (uint256);

    function token() external view returns (IERC20Mintable);

    function releaseAll() external;

    function releaseParticipant(uint8 participant) external;

    function releaseMyTokens() external;

    function releaseTokensOfRole(bytes32 role, uint256 amount) external;

    function release(uint256 index) external;

    function revokeTokensOfParticipant(uint8 participant) external;

    function revokeTokensOfAddress(address beneficiary) external;

    function revokeTokensOfRole(bytes32 role) external;

    function revoke(uint256 index) external;

    function releasableAmount() external view returns (uint256);

    function releasableAmountOfParticipant(uint8 participant)
        external
        view
        returns (uint256);

    function releasableAmountOfAddress(address beneficiary)
        external
        view
        returns (uint256);

    function releasableAmountOfRole(bytes32 role)
        external
        view
        returns (uint256);

    function releasableAmountAt(uint256 index) external view returns (uint256);

    function totalAmount() external view returns (uint256);

    function totalAmountOfParticipant(uint8 participant)
        external
        view
        returns (uint256);

    function totalAmountOfAddress(address beneficiary)
        external
        view
        returns (uint256);

    function totalAmountOfRole(bytes32 role) external view returns (uint256);

    function totalAmountAt(uint256 index) external view returns (uint256);

    function releasedAmount() external view returns (uint256);

    function releasedAmountOfParticipant(uint8 participant)
        external
        view
        returns (uint256);

    function releasedAmountOfAddress(address beneficiary)
        external
        view
        returns (uint256);

    function releasedAmountOfRole(bytes32 role) external view returns (uint256);

    function releasedAmountAt(uint256 index) external view returns (uint256);

    function vestingInfoAt(uint256 index)
        external
        view
        returns (VestingInfo memory);

    function indexesOfBeneficiary(address beneficiary)
        external
        view
        returns (uint256[] memory);

    function indexesOfRole(bytes32 role)
        external
        view
        returns (uint256[] memory);

    function revokedIndexes() external view returns (uint256[] memory);
}
