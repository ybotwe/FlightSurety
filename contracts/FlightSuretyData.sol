//SPDX-License-Identifier: MIT
pragma solidity ^0.4.24;
pragma experimental ABIEncoderV2;
import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner;                                      // Account used to deploy contract
    bool private operational = true;                                    // Blocks all state changes throughout the contract if false

    struct Airline {
        bool registered;
        string name;
        address airlineAddress;
    }

    struct Flight {
        string name;
        bool registered;
        address airline;
        uint256 statusCode;
        uint256 timestamp;
    }

    struct Insurance{
        address passenger;
        uint256 amount;
        Flight flight;
    }

    uint256 private airlineCount = 0; 
    uint256 private insuranceCount = 0;

    bytes32[] private flightKeys = new bytes32[](0);            //Array to track the keys of all registered Flights
    address[] private insurees = new address[](0);              //Array to track all passengers that have purchased insurance

    mapping(bytes32=>Flight) private flights;                   //Mapping for keeping track of flights by flightKeys
    mapping(address => Airline) private airlines;               //Mapping for keeping track of airlines
    mapping(uint => Insurance) private insurances;              //Mapping for keeping track of insurances
    mapping(address => uint256) private payouts;                // Mapping for storing insurance refund payouts
    mapping(address => uint256) private funds;                  // Mapping for storing funds
    mapping(address => uint256) private authorizedContracts;    //Mapping for storing authorizedContracts that can call this contract.



    uint256 public constant MAX_INSURANCE_VALUE = 1 ether;     //highest value of purchasing flight insurance
    uint256 public constant MIN_AIRLINE_FUND = 10 ether;       //minimum value for airlines to participate in contract

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS & CONSTRUCTOR                    */
    /********************************************************************************************/

    event InsureeCredited(address insuree, uint credit, uint total);

    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor
                                (
                                ) 
                                public 
    {
        contractOwner = msg.sender;
    }


    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in 
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational() 
    {
        require(operational, "Contract is currently not operational");
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner()
    {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    /**
    * @dev Modifier to check whether function was called from authorized contract
    */
    modifier isAuthorizedCaller(){
        require(authorizedContracts[msg.sender] == 1, "Caller is not authorized");
        _;
    }

    /**
    * @dev Modifier to check whether insuree is paying within the accurate range of 0 - 1 ether 
    */
    modifier accurateInsureePayment(){
        require(msg.value > 0 && msg.value <= MAX_INSURANCE_VALUE, "Insuree payment should be between 0 - 1 ether");
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
    * @dev Get operating status of contract
    *
    * @return A bool that is the current operating status
    */      
    function isOperational() 
                            public 
                            view 
                            returns(bool) 
    {
        return operational;
    }


    /**
    * @dev Sets contract operations on/off
    *
    * When operational mode is disabled, all write transactions except for this one will fail
    */    
    function setOperatingStatus
                            (
                                bool mode
                            ) 
                            external
                            requireContractOwner 
    {
        operational = mode;
    }

    /**
    * @dev Authorizes an external contract to call this contract
    */
    function authorizeCaller(address caller) public view requireContractOwner {
        require(authorizedContracts[caller] == 0, "Caller already authorized");
        authorizedContracts[caller] == 1;
    }

    /**
    * @dev Deauthorizes an external contract to call this contract
    */
    function deauthorizeCaller(address caller) public view requireContractOwner {
        require(authorizedContracts[caller] == 1, "Caller not initially authorized");
        authorizedContracts[caller] == 0;
    }
    


    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

   /**
    * @dev Add an airline to the registration queue
    *      Can only be called from FlightSuretyApp contract
    *
    */   
    function registerAirline
                            ( 
                                string name,
                                address airlineAddress  
                            )
                            external
                            isAuthorizedCaller
                            requireIsOperational
    {
        require(!airlines[airlineAddress].registered, "Airline is already registered");
        airlines[airlineAddress] = Airline({name: name, registered: true, airlineAddress: airlineAddress});
        airlineCount = airlineCount.add(1);
    }

    /**
    * @dev To get the number of airlines registered
    */
    function getAirlineCount() public view returns (uint256) {
        return airlineCount;
    }

     /**
    * @dev To check whether the specific airline is registered
    */
    function isAirlineRegistered(address wallet) external view returns (bool) {
        return airlines[wallet].registered;
    }

    /**
    * @dev To check whether the specific airline meets the minimum funds requirement
    */
    function isAirlineFunded(address wallet) external view returns (bool) {
        return funds[wallet] >= MIN_AIRLINE_FUND;
    }


    /**
    * @dev To check whether the specific flight is already registered
    */
    function isFlightRegistered(string memory name, uint256 timestamp, address airline) public view returns (bool) {
        bytes32 id = getFlightKey(airline, name, timestamp);
        return flights[id].registered;
    }

    /**
    * @dev To register flights
    */
    function registerFlight(string name, uint256 timestamp, address airline) external isAuthorizedCaller {
        bool registered = isFlightRegistered(name, timestamp, airline);
        require(!registered, "Flight is already registered");
        bytes32 id = getFlightKey(airline, name, timestamp);
        require(!flights[id].registered, "Flight is already registered.");
        flights[id].name = name;
        flights[id].registered = true;
        flights[id].airline = airline;
        flights[id].statusCode = 0;
        flights[id].timestamp = timestamp;
        flightKeys.push(id);
    }

     /**
    * @dev To get the information about the specific airline (this function can be requested from front-end)
    */
    function getFlights() external view returns (string[] memory, address[] memory, uint256[] memory) {
        uint l = flightKeys.length;
        string[] memory names = new string[](l);
        address[] memory airline_addr = new address[](l);
        uint256[] memory timestamps = new uint256[](l);

        for (uint i = 0; i < l; ++i) {
            bytes32 key = flightKeys[i];
            names[i] = flights[key].name;
            airline_addr[i] = flights[key].airline;
            timestamps[i] = flights[key].timestamp;
        }
        return (names, airline_addr, timestamps);
    }

    /**
    * @dev To check any funds owed to the passenger
    */
    function checkFunds(address insuree) external view returns (uint){
        return payouts[insuree];
    }


   /**
    * @dev Buy insurance for a flight
    *
    */   
    function buy
                            (  
                                string flight,
                                uint256 timestamp,
                                address airline,
                                address insuree
                            )
                            external
                            payable
                            isAuthorizedCaller
                            accurateInsureePayment
                            requireIsOperational
    {
        bytes32 id = getFlightKey(airline, flight, timestamp);
        require(flights[id].registered, "Flight does not exist");
        
        uint insurance_amount = 0; 
        if(msg.value >= MAX_INSURANCE_VALUE){
            insurance_amount = MAX_INSURANCE_VALUE;
        } else {
            insurance_amount = msg.value;
        }

        insurances[insuranceCount].flight = flights[id];
        insurances[insuranceCount].passenger = insuree;
        insurances[insuranceCount].amount = insurance_amount;
        insuranceCount = insuranceCount.add(1);
        insurees.push(insuree);
    }

    /**
     *  @dev Credits payouts to insurees
    */
    function creditInsurees
                                (
                                    string flight,
                                    uint256 timestamp,
                                    address airline
                                )
                                external
                                requireIsOperational
    {
        bytes32 id = getFlightKey(airline, flight, timestamp);
        for (uint i = 0; i < insurees.length; ++i) {
            address insuree = insurances[i].passenger;
            bytes32 id2 = getFlightKey(insurances[i].flight.airline, insurances[i].flight.name, insurances[i].flight.timestamp);

            if(insurances[i].amount == 0) continue;
            if (id == id2) {
                uint256 value = insurances[i].amount;
                uint256 half = value.div(2);
                insurances[i].amount = 0;
                uint256 refund = value.add(half);
                payouts[insuree] = payouts[insuree].add(refund);
                emit InsureeCredited(insuree, refund, payouts[insuree]);
            }
        }
    }
    

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function pay
                            (
                                address insuree
                            )
                            external
                            isAuthorizedCaller
    {
        uint256 refund = payouts[insuree];
        payouts[insuree] = 0;
        insuree.transfer(refund);
    }

   /**
    * @dev Initial funding for the insurance. Unless there are too many delayed flights
    *      resulting in insurance payouts, the contract should be self-sustaining
    *
    */   
    function fund
                            (  
                                address sender 
                            )
                            public
                            payable
    {
        require(msg.value > 0, "Funds must be greater than 0");
        funds[sender] = funds[sender].add(msg.value);
    }

    function getFlightKey
                        (
                            address airline,
                            string memory flight,
                            uint256 timestamp
                        )
                        pure
                        internal
                        returns(bytes32) 
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    /**
    * @dev Fallback function for funding smart contract.
    *
    */
    function () 
                            external
                            payable 
    {
        require(msg.value > 0, "No funds are not allowed");
        fund(msg.sender);
    }


}

