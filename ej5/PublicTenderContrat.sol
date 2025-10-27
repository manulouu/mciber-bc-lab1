// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import "@openzeppelin/contracts/access/Ownable.sol";

contract PublicTender is Ownable {
    enum Status { Open, Closed, Evaluated, Finalized }
    
    struct Tender {
        address creator; 
        string description; 
        uint256 maxPrice;
        uint256 deadline;
        uint8 weightPrice;     
        uint8 weightQuality;    
        Status status;
        address winner;
    }
    
    struct Offer {
        address provider;
        uint256 price;
        string documentation;
        uint8 qualityScore; 
        bool evaluated;
        bool exist;
    }

    mapping(uint256 => Tender) public tenders;
    mapping(uint256 => mapping(address => Offer)) public offers;
    mapping(uint256 => address[]) public participants;
    mapping(address => bool) public evaluators; 

    uint256 public tenderCount;

    constructor(address initialOwner) Ownable(initialOwner) {
        evaluators[initialOwner] = true;
    }

    modifier onlyEvaluator() {
        require(evaluators[msg.sender], "Only evaluators can call this");
        _;
    }


    function addEvaluator(address _evaluator) external onlyOwner {
        require(_evaluator != address(0), "Invalid address");
        require(!evaluators[_evaluator], "Already an evaluator");
        evaluators[_evaluator] = true;
    }

    function removeEvaluator(address _evaluator) external onlyOwner {
        require(evaluators[_evaluator], "Not an evaluator");
        evaluators[_evaluator] = false;
    }

    function addTender(
        string memory _description,
        uint256 _maxPrice,
        uint256 _deadlineInDays,
        uint8 _weightPrice,
        uint8 _weightQuality
    ) external onlyOwner {
        require(_weightPrice + _weightQuality == 100, "Weights must sum 100%");
        require(_maxPrice > 0, "Max price must be > 0");
        require(_deadlineInDays > 0, "Deadline must be > 0");
        require(bytes(_description).length > 0, "Description cannot be empty");
        
        tenderCount++;
        uint256 deadline = block.timestamp + (_deadlineInDays * 1 days);
        
        tenders[tenderCount] = Tender({
            creator: msg.sender,
            description: _description,
            maxPrice: _maxPrice,
            deadline: deadline,
            weightPrice: _weightPrice,
            weightQuality: _weightQuality,
            status: Status.Open,
            winner: address(0)
        });
        
    }

    function closeOfferPeriod(uint256 _tenderId) external onlyOwner {
        Tender storage tender = tenders[_tenderId];
        require(tender.status == Status.Open, "Tender is not open");
        require(block.timestamp > tender.deadline, "Deadline not reached yet");
        require(participants[_tenderId].length > 0, "No offers submitted");
        
        tender.status = Status.Closed;
    }


    function submitOffer(
        uint256 _tenderId,
        uint256 _price,
        string memory _documentationHash
    ) external {
        Tender storage tender = tenders[_tenderId];
        
        require(tender.creator != address(0), "Tender does not exist");
        require(tender.status == Status.Open, "Tender is not accepting offers");
        require(block.timestamp <= tender.deadline, "Deadline has passed");
        require(_price > 0, "Price must be > 0");
        require(_price <= tender.maxPrice, "Price exceeds maximum");
        require(!offers[_tenderId][msg.sender].exist, "Already submitted an offer");
        require(bytes(_documentationHash).length > 0, "Documentation hash required");
        
        offers[_tenderId][msg.sender] = Offer({
            provider: msg.sender,
            price: _price,
            documentation: _documentationHash,
            qualityScore: 0,
            evaluated: false,
            exist: true
        });
        
        participants[_tenderId].push(msg.sender);
        
    }


    function evaluateOffer(
        uint256 _tenderId,
        address _provider,
        uint8 _qualityScore
    ) external onlyEvaluator {
        Tender storage tender = tenders[_tenderId];
        
        require(tender.status == Status.Closed, "Tender must be closed for evaluation");
        require(_qualityScore <= 100, "Quality score must be <= 100");
        
        Offer storage offer = offers[_tenderId][_provider];
        require(offer.exist, "Offer not found");
        require(!offer.evaluated, "Offer already evaluated");

        offer.qualityScore = _qualityScore;
        offer.evaluated = true;
        
    }

    function markAsEvaluated(uint256 _tenderId) external onlyOwner {
        Tender storage tender = tenders[_tenderId];
        require(tender.status == Status.Closed, "Tender must be closed");
        
        
        address[] storage parts = participants[_tenderId];
        require(parts.length > 0, "No offers to evaluate");
        
        for (uint256 i = 0; i < parts.length; i++) {
            require(offers[_tenderId][parts[i]].evaluated, "Not all offers are evaluated");
        }
        
        tender.status = Status.Evaluated;
    }


    function calculateWinner(uint256 _tenderId) external onlyOwner {
        Tender storage tender = tenders[_tenderId];
        require(tender.status == Status.Evaluated, "Tender must be evaluated first");
        require(tender.winner == address(0), "Winner already calculated");

        address best = address(0);
        uint256 bestScore = 0;

        address[] storage parts = participants[_tenderId];
        
        for (uint256 i = 0; i < parts.length; i++) {
            address supplier = parts[i];
            Offer storage offer = offers[_tenderId][supplier];

          
            uint256 priceScore = (tender.maxPrice * 100) / offer.price;
            if (priceScore > 100) priceScore = 100;

            
            uint256 combined = (priceScore * tender.weightPrice + 
                               offer.qualityScore * tender.weightQuality) / 100;

            if (combined > bestScore) {
                bestScore = combined;
                best = supplier;
            }
        }

        require(best != address(0), "No valid winner found");
        
        tender.winner = best;
        tender.status = Status.Finalized;
        
    }


    function getOffer(uint256 _tenderId, address _provider) external view returns (
        uint256 price,
        string memory documentation,
        uint8 qualityScore,
        bool evaluated
    ) {
        Offer memory offer = offers[_tenderId][_provider];
        require(offer.exist, "Offer does not exist");
        return (offer.price, offer.documentation, offer.qualityScore, offer.evaluated);
    }

    function getOffers(uint256 _tenderId) external view returns (
        address[] memory providers,
        uint256[] memory prices,
        uint8[] memory qualityScores,
        uint256[] memory totalScores
    ) {
        address[] memory provs = participants[_tenderId];
        uint256 length = provs.length;
        
        uint256[] memory prcs = new uint256[](length);
        uint8[] memory qScores = new uint8[](length);
        uint256[] memory tScores = new uint256[](length);

        Tender memory tender = tenders[_tenderId];
        
        for (uint256 i = 0; i < length; i++) {
            Offer memory offer = offers[_tenderId][provs[i]];
            prcs[i] = offer.price;
            qScores[i] = offer.qualityScore;

            if (offer.evaluated) {
                uint256 priceScore = (tender.maxPrice * 100) / offer.price;
                if (priceScore > 100) priceScore = 100;
                tScores[i] = (priceScore * tender.weightPrice + 
                             offer.qualityScore * tender.weightQuality) / 100;
            }
        }
        
        return (provs, prcs, qScores, tScores);
    }

   function getTender(uint256 _tenderId) public view returns (
    string memory description,
    uint256 maxPrice,
    uint256 deadline,
    Status status,
    address winner,
    uint256 participantCount
) {
    
    require(tenders[_tenderId].creator != address(0), "Tender does not exist");

    Tender storage tender = tenders[_tenderId]; 
    return (
        tender.description,
        tender.maxPrice,
        tender.deadline,
        tender.status,
        tender.winner,
        participants[_tenderId].length
    );
}

    function getParticipants(uint256 _tenderId) external view returns (address[] memory) {
        return participants[_tenderId];
    }

    function isEvaluator(address _address) external view returns (bool) {
        return evaluators[_address];
    }
}
