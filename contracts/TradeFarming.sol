//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
/* 
    DEX'lerdeki swap fonksiyonlarını interface'e ekledim
    Tüm Uniswap v2 forku dexler ile uyumlu çalışacak durumdayız -> yani Avalanche'ta hepsi
*/
import "./IDEXRouter.sol";
/*
    ERC-20 Interface'i
    Swap ve ödül tokenlarında kullanılacak
*/
import "./IERC20.sol";


// çalışacak olan trade farming kontratı bu kısım. sonrasında bir factory kontratın bu kontratı üreteceği bir yapıya geçeceğiz
// bu örnek AVAX-token çiftleri için token cinsinden hacim takip ederek yarışma düzenliyor
contract TradeFarming is Ownable {
    using EnumerableSet for EnumerableSet.UintSet; // kullanıcıların trade ettiği günleri tutacağımız set

    address private immutable routerAddress; // dex router adresimiz
    uint256 private immutable deployTime; // yarışma başlama anı timestampi
    DEXRouter routerContract; // router instanceımız
    IERC20 tokenContract; // yarışma token contractımız
    IERC20 rewardToken; // ödül token contractımız (png)

    mapping(uint256 => uint256) private previousVolumes; // belirtilen günden önceki günlerin hacim ortalaması kaç
    uint private previousDay; // yarışma başlamadan önce kaç günlük hacim ortalaması verisi dahil edildi
    uint private lastAddedDay = 0; // en son hangi günde önceki günün ortalama hesabı yapıldı
    uint private totalRewardBalance = 0; // dağıtılmamış toplam ödül havuzu miktarı
    uint private totalDays;

    mapping(address => mapping(uint256 => uint256)) public volumeRecords; // kullanıcıların yarışma günlerine ait hacimleri
    mapping(uint => uint) public dailyVolumes; // günlük toplam hacimler
    mapping(uint => uint) public dailyRewards; // günlük ödüller

    mapping(address => EnumerableSet.UintSet) tradedDays; // kullanıcıların yarıştığı günler

    uint constant MAX_UINT = 2**256 - 1;

    constructor(
        address _routerAddress,
        address _tokenAddress,
        address _rewardAddress,
        uint _previousVolume,
        uint _previousDay,
        uint _totalDays
    ) {
        routerAddress = _routerAddress;
        deployTime = block.timestamp;
        routerContract = DEXRouter(_routerAddress);
        tokenContract = IERC20(_tokenAddress);
        rewardToken = IERC20(_rewardAddress);
        previousVolumes[0] = _previousVolume;
        previousDay = _previousDay;
        tokenContract.approve(address(routerContract), MAX_UINT);
        rewardToken.approve(owner(), MAX_UINT);
        totalDays = _totalDays;
    }

    // Ödül havuzuna (kontratın kendisi) token yatırmaya yarar
    function depositRewardTokens(uint amount) public onlyOwner {
        require(rewardToken.balanceOf(msg.sender) >= amount, "Not enough balance!");
        require(rewardToken.allowance(msg.sender, address(this)) >= amount, "Not enough allowance!");
        require(rewardToken.transferFrom(msg.sender, address(this), amount));
        totalRewardBalance = totalRewardBalance + amount;
    }

    // Ödül havuzundan (kontratın kendisi) token çekmeye yarar
    function withdrawRewardTokens(uint amount) public onlyOwner {
        require(rewardToken.balanceOf(address(this)) >= amount, "Not enough balance!");
        require(rewardToken.transferFrom(address(this), msg.sender, amount));
        totalRewardBalance = totalRewardBalance - amount;
    }

    // Yarışmanın toplam süresini değiştirmeye yarar
    function changeTotalDays(uint _newTotalDays) public onlyOwner {
        totalDays = _newTotalDays;
    }

    /*
        Kaçıncı günde olduğumuzu hesaplayan fonksiyon
    */
    function calcDay() private view returns (uint256) {
        return (block.timestamp - deployTime) / 1 days;
    }

    /*
        Hacim kayıtlarını tutmak adına swap işleminden sonra çağıracağız
        Modifier olarak kullanmıştım. İptal
    */
    function tradeRecorder(uint256 _volume) private {
        volumeRecords[msg.sender][calcDay()] + _volume;
        dailyVolumes[calcDay()] + _volume;

        if (lastAddedDay + 1 <= calcDay()) {
            addNextDaysToAverage();
        }
    }


    /*
        Belirlenen günün önceki günlerin ortalamasına göre ‰(binde) hacim değişimini verir
    */
    function calculateDayVolumeChange(uint256 _day)
        private
        view
        returns (uint256)
    {
        return (dailyVolumes[_day] * 1000) / previousVolumes[_day];
    }

    /*
        fonksiyon en son hacim hesaplaması yapılan günün ertesi gününün hacmini de hesaplayarak ortalamaya ekler
    */
    function addNextDaysToAverage() private {
        uint256 _cd = calcDay();
        uint256 _pd = previousDay + _cd;
        require(lastAddedDay + 1 <= _cd, "Not ready to operate!");
        previousVolumes[lastAddedDay + 1] =
            (previousVolumes[lastAddedDay] * _pd + dailyVolumes[lastAddedDay]) /
            (_pd + 1);
        
        /*
            Günlük ödül = (ödül havuzunda kalan miktar / kalan gün) * hacmin önceki güne göre değişimi
        */
        dailyRewards[lastAddedDay] = (totalRewardBalance / (totalDays - lastAddedDay))*calculateDayVolumeChange(lastAddedDay)/1000;
        totalRewardBalance = totalRewardBalance - dailyRewards[lastAddedDay];
        lastAddedDay++;

        if (lastAddedDay + 1 <= _cd) addNextDaysToAverage();
    }

    // Mevcut gün hariç tüm günlere ait ödülleri claim et
    function claimAllRewards() public {
        uint totalRewardOfUser = 0;
        uint rewardRate = 1000;
        for(uint i = 0; i < tradedDays[msg.sender].length(); i++) {
            if(tradedDays[msg.sender].at(i) < calcDay()) {
                rewardRate = (volumeRecords[msg.sender][tradedDays[msg.sender].at(i)] * 1000) 
                    / dailyVolumes[tradedDays[msg.sender].at(i)];
                    totalRewardOfUser += (rewardRate * dailyRewards[tradedDays[msg.sender].at(i)]) / 1000;
                tradedDays[msg.sender].remove(tradedDays[msg.sender].at(i));
            }
        }
        require(totalRewardOfUser > 0, "No reward!");
        require(tokenContract.transferFrom(address(this), msg.sender, totalRewardOfUser));
    }

    function calculateUserRewards() external view returns(uint) {
        uint totalRewardOfUser = 0;
        uint rewardRate = 1000;
        for(uint i = 0; i < tradedDays[msg.sender].length(); i++) {
            if(tradedDays[msg.sender].at(i) < calcDay()) {
                rewardRate = (volumeRecords[msg.sender][tradedDays[msg.sender].at(i)] * 1000) 
                    / dailyVolumes[tradedDays[msg.sender].at(i)];
                    totalRewardOfUser += (rewardRate * dailyRewards[tradedDays[msg.sender].at(i)]) / 1000;
            }
        }
        return totalRewardOfUser;
    }

    // AVAX - token çiftine uygun swapa dair fonksiyon. token alınıyorsa true, token satılıyorsa false gönderilir
    function tradeFarm(bool buyToken, uint volume, uint amountOutMin, uint deadline) external payable returns (uint) {
        if(!tradedDays[msg.sender].contains(calcDay())) tradedDays[msg.sender].add(calcDay());
        if (buyToken) {
            require(msg.value == volume , "Not enough balance!");
            address[] memory path = new address[](2);
            path[0] = routerContract.WAVAX();
            path[1] = address(tokenContract);
            uint out = routerContract.swapExactAVAXForTokens{value: volume}(amountOutMin, path, msg.sender, deadline)[1];
            tradeRecorder(out);
            return out;
        } else {
            require(tokenContract.allowance(msg.sender, address(this)) >= volume, "Not enough allowance!");
            require(tokenContract.transferFrom(msg.sender, address(this), volume));
            address[] memory path = new address[](2);
            path[0] = address(tokenContract);
            path[1] = routerContract.WAVAX();
            tradeRecorder(volume);
            return routerContract.swapExactTokensForAVAX(volume, amountOutMin, path, msg.sender, deadline)[1];
        }
    }
}