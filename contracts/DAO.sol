// SPDX-License-Identifier: MIT

pragma solidity 0.8.29;

import "./tokens/SystemToken.sol";
import "./tokens/WrapToken.sol";

contract DAO {
    SystemToken public systemToken;
    WrapToken public wrapToken;

    mapping(address => bool) internal daoMembers;
    mapping(ProposalType => EventType) internal proposalEventTypes;
    mapping(QuorumMechanism => ProposalType[]) internal quorumMechanismTypes;
    mapping(uint256 => Voting) public votings;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => VotingVotes) public votes;

    enum ProposalType {
        A,
        B,
        C,
        D,
        E,
        F
    }
    enum EventType {
        Invest,
        AddMember,
        DeleteMember,
        ManageSystemToken,
        ManageWrapToken
    }
    enum VotingStatus {
        Decided,
        Undecided,
        Deleted
    }
    enum QuorumMechanism {
        SimpleMajority,
        SuperMajority,
        Weighted
    }

    uint256 systemTokensPerVote;
    uint256[] internal proposalIds;

    struct Proposal {
        ProposalType proposalType;
        address proposedBy;
        address[] targets;
        int256[] values;
        bool isVoted;
    }

    struct Voting {
        VotingStatus votingStatus; // Статус голосования (Принято решение/Не принято/Удален);
        uint256 startAt; // Время начала голосования;
        uint256 endAt; // Время окончания голосования;
        address initiatedBy; // Пользователь, инициировавший голосование;
        uint8 priority; // Приоритет голосования;
        QuorumMechanism quorumMechanism; // Механизм достижения кворума;
        EventType eventType; // Тип ивента, который назначается после положительного решения на голосовании.
    }

    struct Vote {
        bool isVotingFor;
        uint256 tokens;
    }

    struct VotingVotes {
        uint256 forVotes;
        uint256 againstVotes;
        mapping(address => Vote) votes;
        address[] voters;
    }

    constructor(
        address _systemTokenContract,
        address _wrapTokenContract,
        address[] memory _daoMembers
    ) {
        systemToken = SystemToken(_systemTokenContract);
        wrapToken = WrapToken(_wrapTokenContract);

        // Добавление всех указанных аккаунтов в список участников DAO
        for (uint256 i = 0; i < _daoMembers.length; i++) {
            daoMembers[_daoMembers[i]] = true;
        }

        systemTokensPerVote = 3;

        // Привязка ивентов к типу предложения
        proposalEventTypes[ProposalType.A] = EventType.Invest;
        proposalEventTypes[ProposalType.B] = EventType.Invest;
        proposalEventTypes[ProposalType.C] = EventType.AddMember;
        proposalEventTypes[ProposalType.D] = EventType.DeleteMember;
        proposalEventTypes[ProposalType.E] = EventType.ManageSystemToken;
        proposalEventTypes[ProposalType.F] = EventType.ManageWrapToken;

        quorumMechanismTypes[QuorumMechanism.SimpleMajority] = [
            ProposalType.C,
            ProposalType.D,
            ProposalType.E,
            ProposalType.F
        ];
        quorumMechanismTypes[QuorumMechanism.SuperMajority] = [
            ProposalType.C,
            ProposalType.D,
            ProposalType.E,
            ProposalType.F
        ];
        quorumMechanismTypes[QuorumMechanism.Weighted] = [
            ProposalType.A,
            ProposalType.B
        ];
    }

    modifier OnlyDaoMember() {
        require(
            daoMembers[msg.sender],
            "Only Dao members can call this function"
        );
        _;
    }

    /*
    Функция выдвигающая предложение
    Принимает в себя аргументы:
    _proposalType - тип proposal;
    _targets - адрес стартапа (в случае если _proposalType A или B),
    либо адрес аккаунта пользователя (в случае если _proposalType C или D);
    _values - кол-во ETH которое предлагается инвестировать (в случае если _proposalType A или B),
    либо множитель (положительное число) или делитель (отрицательное число) (в случае если _proposalType E или F);
    Во всех случаях, где принимается массив, нужно передавать аргументы именно первым элементом в массиве.
    Если тип proposal не требует _target или _value то передается пустой массив
    */
    function propose(
        ProposalType _proposalType,
        address[] memory _targets,
        int256[] memory _values
    ) public OnlyDaoMember returns (uint256) {
        uint256 proposalId = proposalIds.length + 1;
        proposalIds.push(proposalId);
        proposals[proposalId] = (
            Proposal(_proposalType, msg.sender, _targets, _values, false)
        );
        return proposalId;
    }

    /*
    Функция инициализирующая голосование
    Принимает в себя аргументы:
    _proposalId - айди proposal
    _quorumMechanism - механизм кворума
    _duration - длительность голосования в минутах
    */
    function startVoting(
        uint256 _proposalId,
        QuorumMechanism _quorumMechanism,
        uint256 _duration
    ) public OnlyDaoMember {
        require(_duration > 0, "Duration can't be less than zero");

        Proposal storage proposal = proposals[_proposalId];
        require(proposal.proposedBy != address(0), "Proposal doesn't exists");
        require(proposal.isVoted == false, "Proposal already voted");

        ProposalType[] memory validTypes = quorumMechanismTypes[
            _quorumMechanism
        ];
        bool isQuorumMechanismValid;

        for (uint256 i = 0; i < validTypes.length; i++) {
            if (validTypes[i] == proposal.proposalType) {
                isQuorumMechanismValid = true;
                break;
            }
        }

        if (!isQuorumMechanismValid) {
            revert("Quorum mechanism not match proposal type");
        }

        uint256 currentTime = block.timestamp;
        uint256 endTime = currentTime + (_duration * 60);
        EventType eventType = proposalEventTypes[proposal.proposalType];
        proposal.isVoted = true;
        votings[_proposalId] = Voting(
            VotingStatus.Undecided,
            currentTime,
            endTime,
            msg.sender,
            1,
            _quorumMechanism,
            eventType
        );
    }

    function deleteVoting(uint256 _proposalId) public OnlyDaoMember {
        require(
            proposals[_proposalId].proposedBy == msg.sender,
            "Only propose initiator can delete propose"
        );

        VotingVotes storage proposalVotes = votes[_proposalId];

        if(proposalVotes.voters.length > 0) {
            for(uint256 i = 0; i > proposalVotes.voters.length; i++) {
                address voter = proposalVotes.voters[i];
                systemToken.transferFrom(address(this), voter, proposalVotes.votes[voter].tokens);
            }
        }

        votings[_proposalId].votingStatus = VotingStatus.Deleted;
    }

    function castVote(
        uint256 _proposalId,
        bool _isVotingFor,
        uint256 _tokensAmount
    ) public OnlyDaoMember {
        Voting memory voting = votings[_proposalId];

        require(voting.endAt >= block.timestamp, "Voting already ended");
        require(voting.votingStatus != VotingStatus.Deleted, "Voting deleted");

        VotingVotes storage votingVotes = votes[_proposalId];

        require(votingVotes.votes[msg.sender].tokens == 0, "You already voted");

        if (voting.quorumMechanism == QuorumMechanism.Weighted) {
            require(
                _tokensAmount > systemTokensPerVote,
                "Tokens amount must be more than system tokens per vote"
            );
            systemToken.transferFrom(msg.sender, address(this), _tokensAmount);
            _updateUserVotes(_proposalId, msg.sender, _tokensAmount, _isVotingFor);
        }

        systemToken.transferFrom(msg.sender, address(this), systemTokensPerVote);
        _updateUserVotes(_proposalId, msg.sender, systemTokensPerVote, _isVotingFor);
    }

    function _updateUserVotes(uint256 _proposalId, address _voter, uint256 _tokensAmount, bool _isVotingFor) internal {
        VotingVotes storage votingVotes = votes[_proposalId];

        votingVotes.voters.push(_voter);
        votingVotes.votes[_voter] = Vote(_isVotingFor, _tokensAmount);

        uint256 userVotes = _tokensAmount / systemTokensPerVote;
            if (_isVotingFor) {
                votingVotes.forVotes += userVotes;
            } else {
                votingVotes.againstVotes += userVotes;
            }

    }

    function updateVotingState(uint256 _proposalId) public {
        Voting storage voting = votings[_proposalId];
        
        if(block.timestamp >= voting.endAt) {
            voting.votingStatus = VotingStatus.Decided;
        }
    }

    function quorum(uint256 proposalId) public pure returns (uint256) {
        return 1;
    }
}
