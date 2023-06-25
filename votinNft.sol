// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {IMembership} from "@aragon/osx/core/plugin/membership/IMembership.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {RATIO_BASE, _applyRatioCeiled} from "@aragon/osx/plugins/utils/Ratio.sol";
import {TokenVoting} from "@aragon/osx/plugins/governance/majority-voting/token/TokenVoting.sol";
import {MajorityVotingBase} from "@aragon/osx/plugins/governance/majority-voting/MajorityVotingBase.sol";
import {IMajorityVoting} from "@aragon/osx/plugins/governance/majority-voting/IMajorityVoting.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@otterspace-xyz/contracts/src/Badges.sol";
import "@otterspace-xyz/contracts/src/SpecDataHolder.sol";
import "@otterspace-xyz/contracts/src/Raft.sol";

contract NftVoting is MajorityVotingBase, Badges {
    using SafeCastUpgradeable for uint256;
    Badges private votingNftToken;
    error TokenIsNotValid();
    error NotAdminToken(address sender);
    function initialize(
        IDAO _dao,
        VotingSettings calldata _votingSettings,
        Badges _tokenNft
    ) external initializer {
        __MajorityVotingBase_init(_dao, _votingSettings);
        votingNftToken = _tokenNft;

    }

    function getVotingToken() public view returns (Badges) {
        return votingNftToken;
    }
    //_tokenId the id of the badge
    function createProposal(bytes calldata _metadata,
    IDAO.Action[] calldata _actions,
    uint256 _allowFailureMap,
    uint64 startDate,
    uint64 endDate,
    VoteOption _voteOption,
    bool _tryEarlyExecution,
    uint256 _tokenId
    ) external override tokenExists(_tokenId) returns (uint256 proposalId) {
        uint256 snapShotBlock;
        unchecked{
            snapShotBlock = block.number -1;
        }
        if(!isBadgeValid(_tokenId)){
            revert TokenIsNotValid();
        }
        if(ownerOf(_tokenId) != msg.sender){
            revert NotAdminToken(msg.sender);
        }
        
        require(isAdminActive(_tokenId,msg.sender),"You are not allowed to create Proposal");
        proposalId = _createProposal({
            _creator: _msgSender(),
            _metadata: _metadata,
            _startDate: _startDate,
            _endDate: _endDate,
            _actions: _actions,
            _allowFailureMap: _allowFailureMap
        });

        Proposal storage proposal_ = proposals[proposalId];
        // check block.timestamp <= start and  end >= start + votingSettings.minDuration with _validateProposalDates
        (
            proposal_.parameters.startDate,
            proposal_.parameters.endDate
        ) = _validateProposalDates(_startDate, _endDate);
        proposal_.parameters.snapshotBlock = snapshotBlock.toUint64();
        proposal_.parameters.votingMode = votingMode();
        proposal_.parameters.supportThreshold = supportThreshold();
        //proposal_.parameters.minVotingPower = _applyRatioCeiled(
           // totalVotingPower_,
           // minParticipation()
        //);
        if(_allowFailureMap != 0 ){
            proposal_.allowFailureMap = _allowFailureMap;
        }
        for (uint256 i; i < _actions.length; ) {
            proposal_.actions.push(_actions[i]);
            unchecked {
                ++i;
            }
        }
        if(_voteOption != VoteOption.None){
            vote(proposalId,_voteOption,_tryEarlyExecution);
        }
    }
    function _vote(uint256 _proposalId,
    VoteOption _voteOption,
    address _voter,
    bool _tryEarlyExecution,
    uint256 _tokenId
    ) internal override tokenExists(_tokenId) {
        Proposal Storange proposal_ = proposals[_proposalId];
        uint256 votingPower = balanceOf(_voter);
        VoteOption state = proposal_.voters[_voter];
        if(state != _voteOption ){
            if(_voteOption == VoteOption.Yes){
                if(state == VoteOption.No ){
                    proposal_.tally.no = proposal_.tally.no - votingPower;
                }else if(state == VoteOption.Abstain){
                    proposal_.tally.abstain = proposal_.tally.abstain - votingPower;
                }
            proposal_.tally.yes = proposal_.tally.yes + votingPower;
            }
            else if(_voteOption == VoteOption.NO){
                if(state == VoteOption.Yes ){
                    proposal_.tally.yes = proposal_.tally.yes - votingPower;
                }else if(state == VoteOption.Abstain){
                    proposal_.tally.abstain = proposal_.tally.abstain - votingPower;
                }
            proposal_.tally.yes = proposal_.tally.yes + votingPower;
            }else{
                if(state == VoteOption.Yes ){
                    proposal_.tally.yes = proposal_.tally.yes - votingPower;
                }else if(state == VoteOption.No){
                    proposal_.tally.no = proposal_.tally.no - votingPower;
                }
                proposal_.tally.abstain = proposal_.tally.abstain + votingPower;
            }
        }

        /*
        if (state == VoteOption.Yes) {
            proposal_.tally.yes = proposal_.tally.yes - votingPower;
        } else if (state == VoteOption.No) {
            proposal_.tally.no = proposal_.tally.no - votingPower;
        } else if (state == VoteOption.Abstain) {
            proposal_.tally.abstain = proposal_.tally.abstain - votingPower;
        }

        // write the updated/new vote for the voter.
        if (_voteOption == VoteOption.Yes) {
            proposal_.tally.yes = proposal_.tally.yes + votingPower;
        } else if (_voteOption == VoteOption.No) {
            proposal_.tally.no = proposal_.tally.no + votingPower;
        } else if (_voteOption == VoteOption.Abstain) {
            proposal_.tally.abstain = proposal_.tally.abstain + votingPower;
        }
        */
        proposal_.voters[_voter] = _voteOption;

        emit VoteCast({
            proposalId: _proposalId,
            voter: _voter,
            voteOption: _voteOption,
            votingPower: votingPower
        });

        if (_tryEarlyExecution && _canExecute(_proposalId)) {
            _execute(_proposalId);
        }
    }
    function _canvote(uint256 _proposalId,address _account,VoteOption _voteoption, uint256 _tokenId) internal view override returns(bool){
        Proposal storage proposal_ = proposals[_proposalId];
        if(!_isProposalOpen(proposal_)){
            return false;
        }
        if(_voteoption != VoteOption.None){
            return false;
        }
        if(ownerOf(_tokenId) != msg.sender || balanceOf(msg.sender)==0){
            return false;
        }
        if(!isBadgeValid(_tokenId)){
            return false;
        }
        if (
            proposal_.voters[_account] != VoteOption.None &&
            proposal_.parameters.votingMode != VotingMode.VoteReplacement
        ) {
            return false;
        }

    }
    uint256[49] private __gap;
}
