/**
 * List of Gods 
 * LGC Token V1.0
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Address.sol";

abstract contract Tokenomics {
   
    uint16  internal constant FEES_DIVISOR = 10**3;
    uint8   internal constant DECIMALS = 6;
    uint256 internal constant ZEROES = 10**DECIMALS;
    
    uint256 private constant MAX = ~uint256(0);
    uint256 internal constant TOTAL_SUPPLY = 100000000000 * ZEROES;
    uint256 internal _reflectedSupply = (MAX - (MAX % TOTAL_SUPPLY));

    uint256 internal constant maxTransactionAmount = TOTAL_SUPPLY / 400; 
    
    uint256 internal constant maxWalletBalance = TOTAL_SUPPLY / 200; 

    uint256 internal constant maxTransactionAmountAtBeginning = 3000000;

    uint256 internal constant maxTransactionAmountAtBeginningTimeLimit = 300;
    
    address internal burnAddress = 0x000000000000000000000000000000000000dEaD;

    enum FeeType { Antiwhale, Burn, Liquidity, Rfi, Nft  }
    struct Fee {
        FeeType name;
        uint256 value;
        address recipient;
        uint256 total;
    }

    Fee[] internal fees;
    uint256 internal sumOfFees;

    constructor() {
        _addFees();
    }

    function _addFee(FeeType name, uint256 value, address recipient) private {
        fees.push( Fee(name, value, recipient, 0 ) );
        sumOfFees += value;
    }

    function _addFees() private {

        _addFee(FeeType.Rfi, 20, address(this) ); 
        _addFee(FeeType.Burn, 20, burnAddress );
        _addFee(FeeType.Nft, 10,  address(this));
    }

    function _getFeesCount() internal view returns (uint256){ return fees.length; }

    function _getFeeStruct(uint256 index) private view returns(Fee storage){
        require( index >= 0 && index < fees.length, "FeesSettings._getFeeStruct: Fee index out of bounds");
        return fees[index];
    }
    function _getFee(uint256 index) internal view returns (FeeType, uint256, address, uint256){
        Fee memory fee = _getFeeStruct(index);
        return ( fee.name, fee.value, fee.recipient, fee.total );
    }
    function _addFeeCollectedAmount(uint256 index, uint256 amount) internal {
        Fee storage fee = _getFeeStruct(index);
        fee.total = fee.total + (amount);
    }

    function getCollectedFeeTotal(uint256 index) internal view returns (uint256){
        Fee memory fee = _getFeeStruct(index);
        return fee.total;
    }
}

abstract contract Presaleable is Ownable {
    bool internal isInPresale = true;
    uint256 internal _ContractStartTime;

    function setPresale(bool value) external onlyOwner {
        isInPresale = value;
        _ContractStartTime = block.timestamp;
    }

    function getPresale() external view onlyOwner returns(bool){
        return (isInPresale);
    }
}

abstract contract Pausable is Context {
    event Paused(address account);

    event Unpaused(address account);

    bool private _paused;

    constructor () {
        _paused = false;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }

    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

abstract contract BaseRfiToken is IERC20, IERC20Metadata, Ownable, Presaleable, Pausable, Tokenomics {

    using Address for address;


    mapping (address => uint256) internal _reflectedBalances;
    mapping (address => uint256) internal _balances;
    mapping (address => mapping (address => uint256)) internal _allowances;
    
    mapping (address => bool) internal _isExcludedFromFee;
    mapping (address => bool) internal _isExcludedFromRewards;
    mapping (address => bool) internal _isUnlimitedAddress;

    address[] private _excluded;
    
    constructor(){
        
        _reflectedBalances[owner()] = _reflectedSupply;
        
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[burnAddress] = true;
        
        _exclude(owner());
        _exclude(address(this));
        _exclude(burnAddress);

        _isUnlimitedAddress[owner()] = true;
        _isUnlimitedAddress[address(this)] = true;
        _isUnlimitedAddress[burnAddress] = true;

        emit Transfer(address(0), owner(), TOTAL_SUPPLY);
    }
    
        function decimals() external pure override returns (uint8) { return DECIMALS; }
        
        function totalSupply() external pure override returns (uint256) {
            return TOTAL_SUPPLY;
        }
        
        function balanceOf(address account) public view override returns (uint256){
            if (_isExcludedFromRewards[account]) return _balances[account];
            return tokenFromReflection(_reflectedBalances[account]);
        }
        
        function transfer(address recipient, uint256 amount) external override returns (bool){
            _transfer(_msgSender(), recipient, amount);
            return true;
        }
        
        function allowance(address owner, address spender) external view override returns (uint256){
            return _allowances[owner][spender];
        }
    
        function approve(address spender, uint256 amount) external override returns (bool) {
            _approve(_msgSender(), spender, amount);
            return true;
        }
        
        function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool){
            _transfer(sender, recipient, amount);

            uint256 currentAllowance = _allowances[sender][_msgSender()];
            require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
            _approve(sender, _msgSender(), currentAllowance - amount);

            return true;
        }

    function burn(uint256 amount) external {

        address sender = _msgSender();
        require(sender != address(0), "BaseRfiToken: burn from the zero address");
        require(sender != address(burnAddress), "BaseRfiToken: burn from the burn address");

        uint256 balance = balanceOf(sender);
        require(balance >= amount, "BaseRfiToken: burn amount exceeds balance");

        uint256 reflectedAmount = amount * (_getCurrentRate());

        _reflectedBalances[sender] = _reflectedBalances[sender] - (reflectedAmount);
        if (_isExcludedFromRewards[sender])
            _balances[sender] = _balances[sender] - (amount);

        _burnTokens( sender, amount, reflectedAmount );
    }
    
    function _burnTokens(address sender, uint256 tBurn, uint256 rBurn) internal {

        _reflectedBalances[burnAddress] = _reflectedBalances[burnAddress] + (rBurn);
        if (_isExcludedFromRewards[burnAddress])
            _balances[burnAddress] = _balances[burnAddress] + (tBurn);

        emit Transfer(sender, burnAddress, tBurn);
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + (addedValue));
        return true;
    }
    
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        return true;
    }
    
    function isExcludedFromReward(address account) external view returns (bool) {
        return _isExcludedFromRewards[account];
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) external view returns(uint256) {
        require(tAmount <= TOTAL_SUPPLY, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount,,,,) = _getValues(tAmount,0);
            return rAmount;
        } else {
            (,uint256 rTransferAmount,,,) = _getValues(tAmount,_getSumOfFees(_msgSender(), tAmount));
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount) internal view returns(uint256) {
        require(rAmount <= _reflectedSupply, "Amount must be less than total reflections");
        uint256 currentRate = _getCurrentRate();
        return rAmount / (currentRate);
    }
    
    function excludeFromReward(address account) external onlyOwner() {
        require(!_isExcludedFromRewards[account], "Account is not included");
        _exclude(account);
    }
    
    function _exclude(address account) internal {
        if(_reflectedBalances[account] > 0) {
            _balances[account] = tokenFromReflection(_reflectedBalances[account]);
        }
        _isExcludedFromRewards[account] = true;
        _excluded.push(account);
    }

    function includeInReward(address account) external onlyOwner() {
        require(_isExcludedFromRewards[account], "Account is not excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _balances[account] = 0;
                _isExcludedFromRewards[account] = false;
                _excluded.pop();
                break;
            }
        }
    }
    
    function setExcludedFromFee(address account, bool value) external onlyOwner { _isExcludedFromFee[account] = value; }
    function isExcludedFromFee(address account) public view returns(bool) { return _isExcludedFromFee[account]; }
    
    function setUnlimitedAddress(address account, bool value) external onlyOwner { _isUnlimitedAddress[account] = value; }
    function isUnlimitedAddress(address account) public view returns(bool) { return _isUnlimitedAddress[account]; }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "BaseRfiToken: approve from the zero address");
        require(spender != address(0), "BaseRfiToken: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
    
    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "BaseRfiToken: transfer from the zero address");
        require(recipient != address(0), "BaseRfiToken: transfer to the zero address");
        require(sender != address(burnAddress), "BaseRfiToken: transfer from the burn address");
        require(amount > 0, "Transfer amount must be greater than zero");
        
        bool takeFee = true;

        if ( isInPresale ){ takeFee = false; }
        else {
            if ( block.timestamp < (_ContractStartTime + maxTransactionAmountAtBeginningTimeLimit) && amount > maxTransactionAmountAtBeginning)
            {
                revert("Transfer amount exceeds the transaction limit in the first a few minutes.");
            }

            if ( amount > maxTransactionAmount && !isUnlimitedAddress(sender) ){
                revert("Transfer amount exceeds the limit of transaction.");
            }

            if ( maxWalletBalance > 0 && !isUnlimitedAddress(recipient)){
                uint256 recipientBalance = balanceOf(recipient);
                require(recipientBalance + amount <= maxWalletBalance, "New balance would exceed the wallet balance limit.");
            }
        }

        if(_isExcludedFromFee[sender] || _isExcludedFromFee[recipient]){ takeFee = false; }

        _beforeTokenTransfer(sender, recipient, amount, takeFee);
        _transferTokens(sender, recipient, amount, takeFee);
        
    }

    function _transferTokens(address sender, address recipient, uint256 amount, bool takeFee) private {
    
        uint256 sumOfFees = _getSumOfFees(sender, amount);
        if ( !takeFee ){ sumOfFees = 0; }
        
        (uint256 rAmount, uint256 rTransferAmount, uint256 tAmount, uint256 tTransferAmount, uint256 currentRate ) = _getValues(amount, sumOfFees);
        
        _reflectedBalances[sender] = _reflectedBalances[sender] - (rAmount);
        _reflectedBalances[recipient] = _reflectedBalances[recipient] + (rTransferAmount);

        if (_isExcludedFromRewards[sender]){ _balances[sender] = _balances[sender] - (tAmount); }
        if (_isExcludedFromRewards[recipient] ){ _balances[recipient] = _balances[recipient] + (tTransferAmount); }
        
        _takeFees( amount, currentRate, sumOfFees );
        emit Transfer(sender, recipient, tTransferAmount);
    }
    
    function _takeFees(uint256 amount, uint256 currentRate, uint256 sumOfFees ) private {
        if ( sumOfFees > 0 && !isInPresale ){
            _takeTransactionFees(amount, currentRate);
        }
    }
    
    function _getValues(uint256 tAmount, uint256 feesSum) internal view returns (uint256, uint256, uint256, uint256, uint256) {
        
        uint256 tTotalFees = tAmount * feesSum / FEES_DIVISOR;
        uint256 tTransferAmount = tAmount - tTotalFees;
        uint256 currentRate = _getCurrentRate();
        uint256 rAmount = tAmount * currentRate;
        uint256 rTotalFees = tTotalFees *  currentRate;
        uint256 rTransferAmount = rAmount - rTotalFees;
        
        return (rAmount, rTransferAmount, tAmount, tTransferAmount, currentRate);
    }
    
    function _getCurrentRate() internal view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply / (tSupply);
    }
    
    function _getCurrentSupply() internal view returns(uint256, uint256) {
        uint256 rSupply = _reflectedSupply;
        uint256 tSupply = TOTAL_SUPPLY;  

        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_reflectedBalances[_excluded[i]] > rSupply || _balances[_excluded[i]] > tSupply) return (_reflectedSupply, TOTAL_SUPPLY);
            rSupply = rSupply - (_reflectedBalances[_excluded[i]]);
            tSupply = tSupply - (_balances[_excluded[i]]);
        }
        if (tSupply == 0 || rSupply < _reflectedSupply / (TOTAL_SUPPLY)) return (_reflectedSupply, TOTAL_SUPPLY);
        return (rSupply, tSupply);
    }
    
    function _beforeTokenTransfer(address sender, address recipient, uint256 amount, bool takeFee) internal virtual;
    
    function _getSumOfFees(address sender, uint256 amount) internal view virtual returns (uint256);

    function _redistribute(uint256 amount, uint256 currentRate, uint256 fee, uint256 index) internal {
        uint256 tFee = amount * (fee) / (FEES_DIVISOR);
        uint256 rFee = tFee * (currentRate);

        _reflectedSupply = _reflectedSupply - (rFee);
        _addFeeCollectedAmount(index, tFee);
    }

    function _takeTransactionFees(uint256 amount, uint256 currentRate) internal virtual;
}

abstract contract NftReward is Ownable, BaseRfiToken {
    bool internal _EnableNft;
    uint256 internal _NftRewardTotal = 0;
    address internal NftManager = owner();

    function setNftManager(address Manager) external onlyOwner{
        NftManager = Manager;
    }

    function getNftManager() external view onlyOwner returns(address) {
        return NftManager;
    }

    function TransferNftReward(address recipient, uint256 amount) external {
        require(NftManager == msg.sender, "Only manager can do it.");

        _transfer(address(this), recipient, amount);
    }

    function BalanceOfNftReward() external view returns(uint256){
        return _NftRewardTotal;
    }
}

contract LgcToken is NftReward {
    string private _name;
    string private _symbol;

    constructor(string memory __name, string memory __symbol){
    
        _name = __name;
        _symbol = __symbol;
    }

    function name() external view override returns (string memory) { return _name; }

    function symbol() external view override returns (string memory) { return _symbol; }
   
    function _beforeTokenTransfer(address sender, address , uint256 , bool ) internal view override {
        if (isInPresale) {
            require(msg.sender == owner(), "Only owner can transfer in presale phase");
        }
        require(!paused(), "ERC20Pausable: token transfer while paused");
    }

    function _getSumOfFees(address sender, uint256 amount) internal view override returns (uint256){ 
        return sumOfFees;
    }

    function _takeTransactionFees(uint256 amount, uint256 currentRate) internal override {
        
        if( isInPresale ){ return; }

        uint256 feesCount = _getFeesCount();
        for (uint256 index = 0; index < feesCount; index++ ){
            (FeeType feename, uint256 value, address recipient,) = _getFee(index);

            if ( value == 0 ) continue;

            if ( feename == FeeType.Rfi ){
                _redistribute( amount, currentRate, value, index );
            }
            else if ( feename == FeeType.Burn ){
                _burn( amount, currentRate, value, index );
            }
            else if ( feename == FeeType.Nft){
                _takeFee( amount, currentRate, value, recipient, index );
            }
            else {
                _takeFee( amount, currentRate, value, recipient, index );
            }
        }
    }

    function _burn(uint256 amount, uint256 currentRate, uint256 fee, uint256 index) private {
        uint256 tBurn = amount * (fee) / (FEES_DIVISOR);
        uint256 rBurn = tBurn * (currentRate);

        _burnTokens(address(this), tBurn, rBurn);
        _addFeeCollectedAmount(index, tBurn);
    }

    function _takeFee(uint256 amount, uint256 currentRate, uint256 fee, address recipient, uint256 index) private {

        uint256 tAmount = amount * (fee) / (FEES_DIVISOR);
        uint256 rAmount = tAmount * (currentRate);

        _reflectedBalances[recipient] = _reflectedBalances[recipient] + (rAmount);
        if(_isExcludedFromRewards[recipient])
            _balances[recipient] = _balances[recipient] + (tAmount);

        _addFeeCollectedAmount(index, tAmount);
    }
    
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    receive() external payable { 
    	
	}

}

