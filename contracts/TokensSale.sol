// SPDX-License-Identifier: MIT

pragma solidity ^0.8.8;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IERC20WithMetadata.sol";
import "./interfaces/ITokensVesting.sol";

contract TokensSale is AccessControlEnumerable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant MAINTAINER_ROLE = keccak256("MAINTAINER_ROLE");

    struct BatchSaleInfo {
        address recipent;
        address paymentToken;
        uint256 price; // wei per token
        uint256 softCap; // wei
        uint256 hardCap; // wei
        uint256 start;
        uint256 end;
        uint256 releaseTimestamp;
        uint256 tgeCliff;
    }

    enum BatchStatus {
        INACTIVE,
        ACTIVE
    }

    struct VestingPlan {
        uint256 percentageDecimals;
        uint256 tgePercentage;
        uint256 finalPercentage;
        uint256 basis;
        uint256 cliff;
        uint256 duration;
        uint8 participant;
    }

    ITokensVesting public tokensVesting;
    EnumerableSet.UintSet private _batches;
    mapping(uint256 => BatchSaleInfo) public batchSaleInfos;
    mapping(uint256 => VestingPlan) public vestingPlans;
    mapping(uint256 => BatchStatus) public batchStatus;
    mapping(uint256 => EnumerableSet.AddressSet) private _whitelistAddresses;
    mapping(uint256 => uint256) public totalSoldAmount;
    EnumerableSet.UintSet private _supportedParticipants;
    mapping(uint256 => EnumerableSet.AddressSet) private _users;
    mapping(uint256 => uint256) public paymentTransactionsCount;
    mapping(uint256 => mapping(address => uint256)) public soldAmount;
    mapping(uint256 => mapping(address => uint256)) public paymentAmount;

    event BatchSaleUpdated(
        uint256 indexed batchNumber,
        address recipient,
        address paymentToken,
        uint256 price,
        uint256 softCap,
        uint256 hardCap,
        uint256 start,
        uint256 end,
        uint256 releaseTimestamp,
        uint256 tgeCliff
    );
    event BatchStatusUpdated(uint256 indexed batchNumber, uint8 status);
    event VestingPlanUpdated(
        uint256 indexed batchNumber,
        uint256 percentageDecimals,
        uint256 tgePercentage,
        uint256 finalPercentage,
        uint256 basis,
        uint256 cliff,
        uint256 duration,
        uint8 participant
    );
    event WhitelistAddressAdded(
        uint256 indexed batchNumber,
        address indexed buyer
    );
    event WhitelistAddressRemoved(
        uint256 indexed batchNumber,
        address indexed buyer
    );
    event TokensPurchased(
        address indexed buyer,
        uint256 paymentAmount,
        uint256 totalReceivedAmount
    );
    event TokensVestingUpdated(address tokensVesting);

    constructor(address tokenVestingAddress_) {
        _updateTokensVesting(tokenVestingAddress_);
        _supportedParticipants.add(1); // seeding
        _supportedParticipants.add(2); // private sale
        _supportedParticipants.add(3); // public sale

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MAINTAINER_ROLE, _msgSender());
    }

    modifier batchExisted(uint256 batchNumber_) {
        require(
            _batches.contains(batchNumber_),
            "TokensSale: batchNumber_ does not exist"
        );
        _;
    }

    modifier onlySupportedParticipant(uint8 participant) {
        require(
            _supportedParticipants.contains(participant),
            "TokensSale: unsupported participant"
        );
        _;
    }

    function _updateTokensVesting(address tokensVestingAddress_) private {
        require(
            tokensVestingAddress_ != address(0),
            "TokensSale: tokensVestingAddress_ is zero address"
        );
        tokensVesting = ITokensVesting(tokensVestingAddress_);
        emit TokensVestingUpdated(tokensVestingAddress_);
    }

    function _updateBatchSaleInfo(
        uint256 batchNumber_,
        address recipient_,
        address paymentToken_,
        uint256 price_,
        uint256 softCap_,
        uint256 hardCap_,
        uint256 start_,
        uint256 end_,
        uint256 releaseTimestamp_,
        uint256 tgeCliff_
    ) private {
        BatchSaleInfo storage _info = batchSaleInfos[batchNumber_];
        _info.recipent = recipient_;
        _info.paymentToken = paymentToken_;
        _info.price = price_;
        _info.softCap = softCap_;
        _info.hardCap = hardCap_;
        _info.start = start_;
        _info.end = end_;
        _info.releaseTimestamp = releaseTimestamp_;
        _info.tgeCliff = tgeCliff_;

        emit BatchSaleUpdated(
            batchNumber_,
            recipient_,
            paymentToken_,
            price_,
            softCap_,
            hardCap_,
            start_,
            end_,
            releaseTimestamp_,
            tgeCliff_
        );
    }

    /**
     * call stack limit
     * param 0: batchNumber
     * param 1: totalAmount
     * param 2: genesisTimestamp
     */
    function _addBeneficiary(uint256[3] memory params_, address recipent_)
        private
        returns (uint256)
    {
        return
            tokensVesting.addBeneficiary(
                recipent_,
                bytes32(0),
                params_[2],
                params_[1],
                (vestingPlans[params_[0]].tgePercentage * params_[1]) /
                    10**(vestingPlans[params_[0]].percentageDecimals + 2),
                (vestingPlans[params_[0]].finalPercentage * params_[1]) /
                    10**(vestingPlans[params_[0]].percentageDecimals + 2),
                vestingPlans[params_[0]].basis,
                vestingPlans[params_[0]].cliff,
                vestingPlans[params_[0]].duration,
                vestingPlans[params_[0]].participant
            );
    }

    function updateTokensVesting(address tokensVestingAddress_)
        external
        onlyRole(MAINTAINER_ROLE)
    {
        _updateTokensVesting(tokensVestingAddress_);
    }

    function addBatchSale(
        uint256 batchNumber_,
        address recipient_,
        address paymentToken_,
        uint256 price_,
        uint256 softCap_,
        uint256 hardCap_,
        uint256 start_,
        uint256 end_,
        uint256 releaseTimestamp_,
        uint256 tgeCliff_
    ) external onlyRole(MAINTAINER_ROLE) {
        require(batchNumber_ > 0, "TokensSale: batchNumber_ is 0");
        require(
            recipient_ != address(0),
            "TokensSale: recipient_ is zero address"
        );
        require(
            paymentToken_ != address(0),
            "TokensSale: paymentToken_ is zero address"
        );
        require(price_ > 0, "TokensSale: price_ is 0");
        require(
            _batches.add(batchNumber_),
            "TokensSale: batchNumber_ already existed"
        );

        _updateBatchSaleInfo(
            batchNumber_,
            recipient_,
            paymentToken_,
            price_,
            softCap_,
            hardCap_,
            start_,
            end_,
            releaseTimestamp_,
            tgeCliff_
        );
    }

    function updateBatchSaleInfo(
        uint256 batchNumber_,
        address recipient_,
        address paymentToken_,
        uint256 price_,
        uint256 softCap_,
        uint256 hardCap_,
        uint256 start_,
        uint256 end_,
        uint256 releaseTimestamp_,
        uint256 tgeCliff_
    ) external onlyRole(MAINTAINER_ROLE) {
        require(batchNumber_ > 0, "TokensSale: batchNumber_ is 0");
        require(
            recipient_ != address(0),
            "TokensSale: recipient_ is zero address"
        );
        require(
            paymentToken_ != address(0),
            "TokensSale: paymentToken_ is zero address"
        );
        require(price_ > 0, "TokensSale: price_ is 0");
        require(
            _batches.contains(batchNumber_),
            "TokensSale: batchNumber_ does not exist"
        );

        _updateBatchSaleInfo(
            batchNumber_,
            recipient_,
            paymentToken_,
            price_,
            softCap_,
            hardCap_,
            start_,
            end_,
            releaseTimestamp_,
            tgeCliff_
        );
    }

    function updateVestingPlan(
        uint256 batchNumber_,
        uint256 percentageDecimals_,
        uint256 tgePercentage_,
        uint256 finalPercentage_,
        uint256 basis_,
        uint256 cliff_,
        uint256 duration_,
        uint8 participant_
    )
        external
        onlyRole(MAINTAINER_ROLE)
        batchExisted(batchNumber_)
        onlySupportedParticipant(participant_)
    {
        require(
            tgePercentage_ + finalPercentage_ <= 100 * 100**percentageDecimals_,
            "TokensSale: bad args"
        );
        VestingPlan storage _plan = vestingPlans[batchNumber_];
        _plan.percentageDecimals = percentageDecimals_;
        _plan.tgePercentage = tgePercentage_;
        _plan.finalPercentage = finalPercentage_;
        _plan.basis = basis_;
        _plan.cliff = cliff_;
        _plan.duration = duration_;
        _plan.participant = participant_;

        emit VestingPlanUpdated(
            batchNumber_,
            percentageDecimals_,
            tgePercentage_,
            finalPercentage_,
            basis_,
            cliff_,
            duration_,
            participant_
        );
    }

    function updateBatchStatus(uint256 batchNumber_, uint8 status_)
        external
        onlyRole(MAINTAINER_ROLE)
        batchExisted(batchNumber_)
    {
        if (batchStatus[batchNumber_] != BatchStatus(status_)) {
            batchStatus[batchNumber_] = BatchStatus(status_);
            emit BatchStatusUpdated(batchNumber_, status_);
        } else {
            revert("TokensSale: status_ is same as before");
        }
    }

    function addWhitelistAddressToBatch(
        uint256 batchNumber_,
        address whitelistAddress_
    ) external onlyRole(MAINTAINER_ROLE) batchExisted(batchNumber_) {
        require(
            _whitelistAddresses[batchNumber_].add(whitelistAddress_),
            "TokensSale: address is already in whitelist"
        );
    }

    function addWhitelistAddressesToBatch(
        uint256 batchNumber_,
        address[] calldata whitelistAddresses_
    ) external onlyRole(MAINTAINER_ROLE) batchExisted(batchNumber_) {
        require(
            whitelistAddresses_.length > 0,
            "TokensSale: whitelistAddresses_ is empty"
        );
        for (
            uint256 _index = 0;
            _index < whitelistAddresses_.length;
            _index++
        ) {
            require(
                _whitelistAddresses[batchNumber_].add(
                    whitelistAddresses_[_index]
                ),
                "TokensSale: address is already in whitelist"
            );
            emit WhitelistAddressAdded(
                batchNumber_,
                whitelistAddresses_[_index]
            );
        }
    }

    function removeWhitelistAddressOutBatch(
        uint256 batchNumber_,
        address whitelistAddress_
    ) external onlyRole(MAINTAINER_ROLE) batchExisted(batchNumber_) {
        require(
            _whitelistAddresses[batchNumber_].remove(whitelistAddress_),
            "TokensSale: address is not in whitelist"
        );
    }

    function removeWhitelistAddressesOutBatch(
        uint256 batchNumber_,
        address[] calldata whitelistAddresses_
    ) external onlyRole(MAINTAINER_ROLE) batchExisted(batchNumber_) {
        require(
            whitelistAddresses_.length > 0,
            "TokensSale: whitelistAddresses_ is empty"
        );
        for (
            uint256 _index = 0;
            _index < whitelistAddresses_.length;
            _index++
        ) {
            require(
                _whitelistAddresses[batchNumber_].remove(
                    whitelistAddresses_[_index]
                ),
                "TokensSale: address is not in whitelist or already removed"
            );
            emit WhitelistAddressRemoved(
                batchNumber_,
                whitelistAddresses_[_index]
            );
        }
    }

    function whitelistAddresses(uint256 batchNumber_)
        public
        view
        returns (address[] memory)
    {
        return _whitelistAddresses[batchNumber_].values();
    }

    function addParticipant(uint8 participant_)
        external
        onlyRole(MAINTAINER_ROLE)
    {
        require(
            _supportedParticipants.add(participant_),
            "TokensSale: already supported"
        );
    }

    function removeParticipant(uint8 participant_)
        external
        onlyRole(MAINTAINER_ROLE)
    {
        require(
            _supportedParticipants.remove(participant_),
            "TokensSale: participant is not supported or already removed"
        );
    }

    function supportedParticipants() public view returns (uint256[] memory) {
        return _supportedParticipants.values();
    }

    function batches() public view returns (uint256[] memory) {
        return _batches.values();
    }

    function buy(uint256 batchNumber_, uint256 paymentAmount_)
        external
        batchExisted(batchNumber_)
    {
        if (_whitelistAddresses[batchNumber_].length() > 0) {
            require(
                _whitelistAddresses[batchNumber_].contains(_msgSender()),
                "TokensSale: sender is not in whitelist"
            );
        }
        require(
            batchStatus[batchNumber_] == BatchStatus.ACTIVE,
            "TokensSale: the sale is inactive"
        );
        require(
            vestingPlans[batchNumber_].basis != 0,
            "TokensSale: vesting plan is not ready"
        );
        require(
            block.timestamp >= batchSaleInfos[batchNumber_].start,
            "TokensSale: the sale does not start"
        );
        require(
            block.timestamp < batchSaleInfos[batchNumber_].end ||
                batchSaleInfos[batchNumber_].end == 0,
            "TokensSale: the sale is ended"
        );

        IERC20WithMetadata _tokenForSale = IERC20WithMetadata(
            address(tokensVesting.token())
        );
        uint256 _totalReceivedAmount = paymentAmount_ /
            (batchSaleInfos[batchNumber_].price / 10**_tokenForSale.decimals());
        require(
            _totalReceivedAmount >= batchSaleInfos[batchNumber_].softCap,
            "TokensSale: amount is too low"
        );
        require(
            _totalReceivedAmount <=
                batchSaleInfos[batchNumber_].hardCap -
                    totalSoldAmount[batchNumber_],
            "TokensSale: amount is too high"
        );

        paymentTransactionsCount[batchNumber_]++;
        _users[batchNumber_].add(_msgSender());
        paymentAmount[batchNumber_][_msgSender()] += paymentAmount_;
        soldAmount[batchNumber_][_msgSender()] += _totalReceivedAmount;
        totalSoldAmount[batchNumber_] += _totalReceivedAmount;

        IERC20(batchSaleInfos[batchNumber_].paymentToken).safeTransferFrom(
            _msgSender(),
            batchSaleInfos[batchNumber_].recipent,
            paymentAmount_
        );

        uint256 _genesisTimestamp = batchSaleInfos[batchNumber_]
            .releaseTimestamp == 0
            ? block.timestamp + batchSaleInfos[batchNumber_].tgeCliff
            : batchSaleInfos[batchNumber_].releaseTimestamp + batchSaleInfos[batchNumber_].tgeCliff;

        uint256[3] memory _params;
        _params[0] = batchNumber_;
        _params[1] = _totalReceivedAmount;
        _params[2] = _genesisTimestamp;
        uint256 _index = _addBeneficiary(_params, _msgSender());
        uint256 _releasableAmount = tokensVesting.releasableAmountAt(_index);
        if (_releasableAmount > 0) {
            tokensVesting.release(_index);
        }

        emit TokensPurchased(
            _msgSender(),
            paymentAmount_,
            _totalReceivedAmount
        );
    }

    function usersCount(uint256 batchNumber_) public view returns (uint256) {
        return _users[batchNumber_].length();
    }

    function users(uint256 batchNumber_)
        public
        view
        returns (address[] memory)
    {
        return _users[batchNumber_].values();
    }
}
