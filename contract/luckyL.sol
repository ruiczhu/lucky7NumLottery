// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Lottery {
    struct Ticket {
        address buyer;
        string number; // 彩票号码
    }

    struct Winner {
        address winnerAddress;
        string winningNumber;
        string prize;
        uint256 amount;
    }

    Ticket[] public tickets;
    Winner[] public winners; // 存储所有中奖者

    uint256 public ticketPrice = 0.001 ether;
    uint256 public lastDrawTime; // 上次开奖时间
    uint256 public drawInterval = 3 days; // 开奖间隔

    // 奖金设置
    uint256 public firstPrizeAmount; // 一等奖奖池
    uint256 public immutable secondPrizeAmount = 2 ether;
    uint256 public immutable thirdPrizeAmount = 1 ether;
    uint256 public immutable fourthPrizeAmount = 0.5 ether;

    address public owner; // 合约拥有者
    bool public paused = false;

    event TicketPurchased(address indexed buyer, string number, uint256 quantity);
    event LotteryDraw(uint256 drawTime, string winningNumber, Winner[] winners);
    event PrizeDistributed(address indexed winner, string number, string prize, uint256 amount);
    event FundsWithdrawn(address indexed to, uint256 amount); // 提取资金事件
    event Paused();
    event Unpaused();

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    constructor(uint256 _ticketPrice) {
        owner = msg.sender;
        lastDrawTime = block.timestamp;
        firstPrizeAmount = 0;
        ticketPrice = _ticketPrice;
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused();
    }

    // Function to unpause the contract
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused();
    }

    function buyTicket(string memory _number, uint256 _quantity) public payable whenNotPaused{
        require(bytes(_number).length == 7, "Ticket number must be 7 digits");
        for (uint256 i = 0; i < 7; i++) {
            require(
                bytes(_number)[i] >= '0' && bytes(_number)[i] <= '9',
                "Ticket number must be numeric"
            );
        }
        require(msg.value == ticketPrice * _quantity, "Incorrect ETH amount");

        // 计算资金分配
        uint256 totalAmount = msg.value;
        uint256 prizePoolContribution = totalAmount / 2; // 一半用于一等奖奖池

        firstPrizeAmount += prizePoolContribution; // 增加一等奖奖池

        for (uint256 i = 0; i < _quantity; i++) {
            tickets.push(Ticket(msg.sender, _number));
        }

        emit TicketPurchased(msg.sender, _number, _quantity);
    }

    function drawLottery() public onlyOwner whenNotPaused{
        require(block.timestamp >= lastDrawTime + drawInterval, "It's not time to draw yet");
        require(tickets.length > 0, "No tickets purchased");

        // 生成一个随机的 7 位数
        string memory winningNumber = generateRandomNumber();
        delete winners; // 清空之前的中奖者记录

        // 查找中奖者
        uint256 firstPrizeWinnersCount = 0;

        uint256[] memory winningIndexes = new uint256[](tickets.length);
        uint256 winningIndexCount = 0;

        for (uint256 i = 0; i < tickets.length; i++) {
            uint256 difference = compareNumbers(tickets[i].number, winningNumber);
            if (difference == 0) {
                firstPrizeWinnersCount++;
                winningIndexes[winningIndexCount] = i; // 记录一等奖中奖者的索引
                winningIndexCount++;
            } else if (difference == 1) {
                winners.push(Winner(tickets[i].buyer, tickets[i].number, "Second Prize", secondPrizeAmount));
                // payable(tickets[i].buyer).transfer(secondPrizeAmount); // 发送二等奖奖金
                (bool success, ) = payable(tickets[i].buyer).call{value: secondPrizeAmount}("");
                require(success, "Transfer to second prize winner failed");
                emit PrizeDistributed(tickets[i].buyer, tickets[i].number, "Second Prize", secondPrizeAmount);
            } else if (difference == 2) {
                winners.push(Winner(tickets[i].buyer, tickets[i].number, "Third Prize", thirdPrizeAmount));
                // payable(tickets[i].buyer).transfer(thirdPrizeAmount); // 发送三等奖奖金
                (bool success, ) = payable(tickets[i].buyer).call{value: thirdPrizeAmount}("");
                require(success, "Transfer to third prize winner failed");
                emit PrizeDistributed(tickets[i].buyer, tickets[i].number, "Third Prize", thirdPrizeAmount);
            } else if (difference == 3) {
                winners.push(Winner(tickets[i].buyer, tickets[i].number, "Fourth Prize", fourthPrizeAmount));
                // payable(tickets[i].buyer).transfer(fourthPrizeAmount); // 发送四等奖奖金
                (bool success, ) = payable(tickets[i].buyer).call{value: fourthPrizeAmount}("");
                require(success, "Transfer to fourth prize winner failed");
                emit PrizeDistributed(tickets[i].buyer, tickets[i].number, "Fourth Prize", fourthPrizeAmount);
            }
        }

        // 处理一等奖
        if (firstPrizeWinnersCount > 0) {
            // 多人中一等奖，按比例分配
            uint256 prizePerWinner = firstPrizeAmount / firstPrizeWinnersCount;
            uint256 remainder = firstPrizeAmount % firstPrizeWinnersCount;
            for (uint256 j = 0; j < winningIndexCount; j++) {
                address winnerAddress = tickets[winningIndexes[j]].buyer;
                // payable(winnerAddress).transfer(prizePerWinner); // 发送奖金
                winners.push(Winner(winnerAddress, tickets[winningIndexes[j]].number, "First Prize", prizePerWinner));
                (bool success, ) = payable(winnerAddress).call{value: prizePerWinner}("");
                require(success, "Transfer to first prize winner failed");
                emit PrizeDistributed(winnerAddress, tickets[winningIndexes[j]].number, "First Prize", prizePerWinner);
            }
            firstPrizeAmount = remainder; // 清空一等奖奖池
        }

        uint256 remainingBalance = address(this).balance; // 获取合约当前余额
        if (remainingBalance > 0) {
            uint256 amountToWithdraw = remainingBalance - firstPrizeAmount;
            // payable(owner).transfer(amountToWithdraw); // 将剩余资金转移到合约拥有者
            (bool success, ) = payable(owner).call{value: amountToWithdraw}("");
            require(success, "Transfer to owner failed");
            emit FundsWithdrawn(owner, amountToWithdraw); // 记录提取事件
        }

        delete tickets;
        // 更新上次开奖时间
        lastDrawTime = block.timestamp;

        emit LotteryDraw(lastDrawTime, winningNumber, winners); // 记录所有中奖者
    }

    function compareNumbers(string memory _ticketNumber, string memory _winningNumber) internal pure returns (uint256) {
        uint256 differenceCount = 0;
        for (uint256 i = 0; i < 7; i++) {
            if (bytes(_ticketNumber)[i] != bytes(_winningNumber)[i]) {
                differenceCount++;
            }
        }
        return differenceCount;
    }

    function generateRandomNumber() internal view returns (string memory) {
        uint256 randomNum = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao))) % 10000000; // 生成 0 到 9999999 的随机数
        return padNumber(randomNum);
    }

    function padNumber(uint256 _number) internal pure returns (string memory) {
        require(_number < 10000000, "Number must be less than 10000000");
        
        // 转换为字符串并填充前导零
        bytes memory numberBytes = new bytes(7);
        for (uint256 i = 0; i < 7; i++) {
            numberBytes[6 - i] = bytes1(uint8(48 + (_number % 10))); // 48 是字符 '0' 的 ASCII 码
            _number /= 10;
        }
        return string(numberBytes);
    }

    function getTickets() public view returns (Ticket[] memory) {
        return tickets;
    }

    function getWinners() public view returns (Winner[] memory) {
        return winners;
    }

    // Fallback functions to accept Ether
    receive() external payable {}
    fallback() external payable {}
}