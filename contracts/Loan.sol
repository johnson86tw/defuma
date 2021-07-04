//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

contract Loan is SuperAppBase, ERC721 {
    ISuperfluid private _host; // host
    IConstantFlowAgreementV1 private _cfa; // the stored constant flow agreement class address
    ISuperToken private _acceptedToken; // accepted token

    using Counters for Counters.Counter;
    using EnumerableMap for EnumerableMap.UintToAddressMap;
    using EnumerableSet for EnumerableSet.UintSet;

    Counters.Counter private _tokenIds;
    EnumerableMap.UintToAddressMap private _loanToIssuers;
    EnumerableSet.UintSet private _available;

    mapping(uint256 => uint256) private _loanToAmount;

    constructor(
        string memory _name,
        string memory _symbol,
        ISuperfluid host,
        IConstantFlowAgreementV1 cfa,
        ISuperToken acceptedToken
    ) ERC721(_name, _symbol) {
        assert(address(host) != address(0));
        assert(address(cfa) != address(0));
        assert(address(acceptedToken) != address(0));
        //assert(!_host.isApp(ISuperApp(receiver)));

        _host = host;
        _cfa = cfa;
        _acceptedToken = acceptedToken;

        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP;

        _host.registerApp(configWord);
    }

    /**************************************************************************
     * Loan Logic
     *************************************************************************/

    // borrower create a loan
    function createLoan() public returns (uint256) {
        _tokenIds.increment();

        uint256 loanId = _tokenIds.current();
        _loanToIssuers.set(loanId, msg.sender);
        _available.add(loanId);

        return loanId;
    }

    // lender send token to contract and get ERC721 token as credit
    function lend(uint256 _loanId) public payable {
        require(_available.contains(_loanId), "no available loan");
        _safeMint(msg.sender, _loanId);

        _loanToAmount[_loanId] = msg.value;
    }

    // borrower withraw money from contract
    function borrow(uint256 _loanId) public {
        require(_loanToIssuers.get(_loanId) == msg.sender, "not the loan issuer");
        require(_loanToAmount[_loanId] > 0, "no lender lend money to the loan");

        (bool success, ) = msg.sender.call{value: _loanToAmount[_loanId]}("");
        require(success, "fail to withdraw money");
    }

    /**************************************************************************
     * Redirect Logic
        - borrower flow money to the contract with specific tokenId(userData),
          and lender would get the interest with money streaming.
        - lender transfer token to another person, that person will get the
          interest flow from the borrower.
     *************************************************************************/

    function loanCreditor(uint256 tokenId)
        external
        view
        returns (
            uint256 startTime,
            address creditor,
            int96 flowRate
        )
    {
        address _loanCreditor = ownerOf(tokenId);
        if (_loanCreditor != address(0)) {
            (startTime, flowRate, , ) = _cfa.getFlow(_acceptedToken, address(this), _loanCreditor);
            creditor = _loanCreditor;
        }
    }

    // override ERC777 as a hook
    function _beforeTokenTransfer(
        address, /*from*/
        address to,
        uint256 /*tokenId*/
    ) internal override {
        _changeReceiver(to);
    }

    event ReceiverChanged(address receiver); //what is this?

    /// @dev If a new stream is opened, or an existing one is opened
    function _updateOutflow(bytes calldata ctx) private returns (bytes memory newCtx) {
        newCtx = ctx;

        uint256 loanId = abi.decode(_host.decodeCtx(ctx).userData, (uint256));
        address _receiver = ownerOf(loanId);

        // @dev This will give me the new flowRate, as it is called in after callbacks
        int96 netFlowRate = _cfa.getNetFlow(_acceptedToken, address(this));
        (, int96 outFlowRate, , ) = _cfa.getFlow(_acceptedToken, address(this), _receiver);
        int96 inFlowRate = netFlowRate + outFlowRate;
        if (inFlowRate < 0) inFlowRate = -inFlowRate; // Fixes issue when inFlowRate is negative

        // @dev If inFlowRate === 0, then delete existing flow.
        if (outFlowRate != int96(0)) {
            (newCtx, ) = _host.callAgreementWithContext(
                _cfa,
                abi.encodeWithSelector(
                    _cfa.updateFlow.selector,
                    _acceptedToken,
                    _receiver,
                    inFlowRate,
                    new bytes(0) // placeholder
                ),
                "0x",
                newCtx
            );
        } else if (inFlowRate == int96(0)) {
            // @dev if inFlowRate is zero, delete outflow.
            (newCtx, ) = _host.callAgreementWithContext(
                _cfa,
                abi.encodeWithSelector(
                    _cfa.deleteFlow.selector,
                    _acceptedToken,
                    address(this),
                    _receiver,
                    new bytes(0) // placeholder
                ),
                "0x",
                newCtx
            );
        } else {
            // @dev If there is no existing outflow, then create new flow to equal inflow
            (newCtx, ) = _host.callAgreementWithContext(
                _cfa,
                abi.encodeWithSelector(
                    _cfa.createFlow.selector,
                    _acceptedToken,
                    _receiver,
                    inFlowRate,
                    new bytes(0) // placeholder
                ),
                "0x",
                newCtx
            );
        }
    }

    // @dev Change the Receiver of the total flow
    function _changeReceiver(address newReceiver) internal {
        require(newReceiver != address(0), "New receiver is zero address");
        // @dev because our app is registered as final, we can't take downstream apps
        require(!_host.isApp(ISuperApp(newReceiver)), "New receiver can not be a superApp");
        // if (newReceiver == _receiver) return;
        // @dev delete flow to old receiver
        // _host.callAgreement(
        //     _cfa,
        //     abi.encodeWithSelector(_cfa.deleteFlow.selector, _acceptedToken, address(this), _receiver, new bytes(0)),
        //     "0x"
        // );
        // @dev create flow to new receiver
        // _host.callAgreement(
        //     _cfa,
        //     abi.encodeWithSelector(
        //         _cfa.createFlow.selector,
        //         _acceptedToken,
        //         newReceiver,
        //         _cfa.getNetFlow(_acceptedToken, address(this)),
        //         new bytes(0)
        //     ),
        //     "0x"
        // );
        // @dev set global receiver to new receiver
        // _receiver = newReceiver;

        emit ReceiverChanged(newReceiver);
    }

    /**************************************************************************
     * SuperApp callbacks
     *************************************************************************/

    function afterAgreementCreated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, // _agreementId,
        bytes calldata, /*_agreementData*/
        bytes calldata, // _cbdata,
        bytes calldata _ctx
    ) external override onlyExpected(_superToken, _agreementClass) onlyHost returns (bytes memory newCtx) {
        return _updateOutflow(_ctx);
    }

    function afterAgreementUpdated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, //_agreementId,
        bytes calldata, /*_agreementData*/
        bytes calldata, //_cbdata,
        bytes calldata _ctx
    ) external override onlyExpected(_superToken, _agreementClass) onlyHost returns (bytes memory newCtx) {
        return _updateOutflow(_ctx);
    }

    function afterAgreementTerminated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, //_agreementId,
        bytes calldata, /*_agreementData*/
        bytes calldata, //_cbdata,
        bytes calldata _ctx
    ) external override onlyHost returns (bytes memory newCtx) {
        // According to the app basic law, we should never revert in a termination callback
        if (!_isSameToken(_superToken) || !_isCFAv1(_agreementClass)) return _ctx;
        return _updateOutflow(_ctx);
    }

    function _isSameToken(ISuperToken superToken) private view returns (bool) {
        return address(superToken) == address(_acceptedToken);
    }

    function _isCFAv1(address agreementClass) private view returns (bool) {
        return
            ISuperAgreement(agreementClass).agreementType() ==
            keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1");
    }

    modifier onlyHost() {
        require(msg.sender == address(_host), "RedirectAll: support only one host");
        _;
    }

    modifier onlyExpected(ISuperToken superToken, address agreementClass) {
        require(_isSameToken(superToken), "RedirectAll: not accepted token");
        require(_isCFAv1(agreementClass), "RedirectAll: only CFAv1 supported");
        _;
    }
}
