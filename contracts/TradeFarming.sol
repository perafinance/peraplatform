//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
/* 
    DEX'lerdeki swap fonksiyonlarını ve kullandığım lib'leri interface'e ekledim
    Tüm Uniswap v2 forku dexler ile uyumlu çalışacak durumdayız -> yani Avalanche'ta hepsi
*/
import "./interfaces/IUniswapV2Router.sol";
/*
    ERC-20 Interface'i
    Swap ve ödül tokenlarında kullanılacak
*/
import "./interfaces/IERC20.sol";

// çalışacak olan trade farming kontratı bu kısım. sonrasında bir factory kontratın bu kontratı üreteceği bir yapıya geçeceğiz
// bu örnek ETH-token çiftleri için token cinsinden hacim takip ederek yarışma düzenliyor
contract TradeFarming is Ownable {
    using EnumerableSet for EnumerableSet.UintSet; // kullanıcıların trade ettiği günleri tutacağımız set

    uint256 private immutable deployTime; // yarışma başlama anı timestampi
    IUniswapV2Router01 routerContract; // router instanceımız
    IERC20 tokenContract; // yarışma token contractımız
    IERC20 rewardToken; // ödül token contractımız (png)

    mapping(uint256 => uint256) public previousVolumes; // belirtilen günden önceki günlerin hacim ortalaması kaç
    uint256 private previousDay; // yarışma başlamadan önce kaç günlük hacim ortalaması verisi dahil edildi
    uint256 private lastAddedDay = 0; // en son hangi günde önceki günün ortalama hesabı yapıldı
    uint256 public totalRewardBalance = 0; // dağıtılmamış toplam ödül havuzu miktarı
    uint256 public totalDays;

    mapping(address => mapping(uint256 => uint256)) public volumeRecords; // kullanıcıların yarışma günlerine ait hacimleri
    mapping(uint256 => uint256) public dailyVolumes; // günlük toplam hacimler
    mapping(uint256 => uint256) public dailyRewards; // günlük ödüller

    mapping(address => EnumerableSet.UintSet) private tradedDays; // kullanıcıların yarıştığı günler

    uint256 constant MAX_UINT = 2**256 - 1;

    constructor(
        address _routerAddress,
        address _tokenAddress,
        address _rewardAddress,
        uint256 _previousVolume,
        uint256 _previousDay,
        uint256 _totalDays
    ) {
        deployTime = block.timestamp;
        routerContract = IUniswapV2Router01(_routerAddress);
        tokenContract = IERC20(_tokenAddress);
        rewardToken = IERC20(_rewardAddress);
        previousVolumes[0] = _previousVolume;
        previousDay = _previousDay;
        tokenContract.approve(address(routerContract), MAX_UINT);
        rewardToken.approve(owner(), MAX_UINT);
        totalDays = _totalDays;
    }

    // Ödül havuzuna (kontratın kendisi) token yatırmaya yarar
    function depositRewardTokens(uint256 amount) external onlyOwner {
        require(
            rewardToken.balanceOf(msg.sender) >= amount,
            "Not enough balance!"
        );
        require(
            rewardToken.allowance(msg.sender, address(this)) >= amount,
            "Not enough allowance!"
        );
        totalRewardBalance += amount;
        require(rewardToken.transferFrom(msg.sender, address(this), amount));
    }

    // Ödül havuzundan (kontratın kendisi) token çekmeye yarar
    function withdrawRewardTokens(uint256 amount) external onlyOwner {
        require(totalRewardBalance >= amount, "Not enough balance!");
        totalRewardBalance -= amount;
        require(rewardToken.transfer(msg.sender, amount));
    }

    // Yarışmanın toplam süresini değiştirmeye yarar
    function changeTotalDays(uint256 _newTotalDays) external onlyOwner {
        totalDays = _newTotalDays;
    }

    /*
        Kaçıncı günde olduğumuzu hesaplayan fonksiyon
    */
    function calcDay() public view returns (uint256) {
        return (block.timestamp - deployTime) / 1 days;
    }

    /*
        Hacim kayıtlarını tutmak adına swap işleminden sonra çağıracağız
        Modifier olarak kullanmıştım. İptal
    */
    function tradeRecorder(uint256 _volume) private {
        if (calcDay() < totalDays) {
            volumeRecords[msg.sender][calcDay()] += _volume;
            dailyVolumes[calcDay()] += _volume;
        }

        if (lastAddedDay + 1 <= calcDay() && lastAddedDay != totalDays) {
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
        uint256 _pd = previousDay + lastAddedDay + 1;
        require(lastAddedDay + 1 <= _cd, "Not ready to operate!");
        previousVolumes[lastAddedDay + 1] =
            (previousVolumes[lastAddedDay] *
                (_pd - 1) +
                dailyVolumes[lastAddedDay]) /
            _pd;

        /*
            Günlük ödül = (ödül havuzunda kalan miktar / kalan gün) * hacmin önceki güne göre değişimi
            %10 ödül değişim sınırı var
            Swap yoksa ödül yok
        */

        // Hacim değişimlerini %90 - %110 arasında kısıtlıyoruz
        uint256 volumeChange = calculateDayVolumeChange(lastAddedDay);
        if (volumeChange > 1100) {
            volumeChange = 1100;
        } else if (volumeChange < 900) {
            volumeChange = 900;
        }

        dailyRewards[lastAddedDay] =
            ((totalRewardBalance / (totalDays - lastAddedDay)) * volumeChange) /
            1000;
        totalRewardBalance = totalRewardBalance - dailyRewards[lastAddedDay];

        lastAddedDay += 1;

        if (lastAddedDay + 1 <= _cd && lastAddedDay != totalDays) addNextDaysToAverage();
    }

    // Mevcut gün hariç tüm günlere ait ödülleri claim et
    function claimAllRewards() external {
        // Önce tüm hacim hesaplamaları güncel mi kontrol edilir
        if (lastAddedDay + 1 <= calcDay() && lastAddedDay != totalDays) {
            addNextDaysToAverage();
        }

        uint256 totalRewardOfUser = 0;
        uint256 rewardRate = 1000; // FIXME: minimum ödül oranını (hassasiyeti) belirtiyor olacak bu. o yüzden çok daha büyütmeliyiz. (muldiv kullan)
        for (uint256 i = 0; i < tradedDays[msg.sender].length(); i++) {
            if (tradedDays[msg.sender].at(i) < lastAddedDay) {
                rewardRate =
                    (volumeRecords[msg.sender][tradedDays[msg.sender].at(i)] *
                        1000) /
                    dailyVolumes[tradedDays[msg.sender].at(i)];
                totalRewardOfUser +=
                    (rewardRate * dailyRewards[tradedDays[msg.sender].at(i)]) /
                    1000;
                tradedDays[msg.sender].remove(tradedDays[msg.sender].at(i));
            }
        }
        require(totalRewardOfUser > 0, "No reward!");
        require(rewardToken.transfer(msg.sender, totalRewardOfUser));
    }

    // Sadece hesaplaması güncellenen günler için toplam ödülü döner
    // FIXME: hesaplanmamış günü de gösterebilecek bir yol düşün 
    function calculateUserRewards() external view returns (uint256) {
        uint256 totalRewardOfUser = 0;
        uint256 rewardRate = 1000; // FIXME:
        for (uint256 i = 0; i < tradedDays[msg.sender].length(); i++) {
            if (tradedDays[msg.sender].at(i) < lastAddedDay) {
                rewardRate =
                    (volumeRecords[msg.sender][tradedDays[msg.sender].at(i)] *
                        1000) /
                    dailyVolumes[tradedDays[msg.sender].at(i)];
                totalRewardOfUser +=
                    (rewardRate * dailyRewards[tradedDays[msg.sender].at(i)]) /
                    1000;
            }
        }
        return totalRewardOfUser;
    }

    // Bir kullanıcının belirtilen gündeki ödülünü döner
    function calculateDailyUserReward(uint _day) external view returns (uint256) {
        uint256 rewardOfUser = 0;
        uint256 rewardRate = 1000; // FIXME:  
        if (_day < lastAddedDay && tradedDays[msg.sender].contains(_day)) {
                rewardRate =
                    (volumeRecords[msg.sender][_day] *
                        1000) /
                    dailyVolumes[_day];
                rewardOfUser +=
                    (rewardRate * dailyRewards[_day]) /
                    1000;
        }   
        return rewardOfUser;
    }

    // Ödülleri hesaplanmamış bir gün olup olmadığını döner
    function isCalculated() external view returns (bool) {
        return (!(lastAddedDay + 1 <= calcDay() && lastAddedDay != totalDays) || lastAddedDay == totalDays);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory out) {
        if (
            !tradedDays[msg.sender].contains(calcDay()) && calcDay() < totalDays
        ) tradedDays[msg.sender].add(calcDay());
        require(msg.value > 0, "Not enough balance!");

        out = routerContract.swapExactETHForTokens{value: msg.value}(
            amountOutMin,
            path,
            to,
            deadline
        );
        if (lastAddedDay != totalDays) tradeRecorder(out[out.length - 1]);
    }

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory) {
        if (
            !tradedDays[msg.sender].contains(calcDay()) && calcDay() < totalDays
        ) tradedDays[msg.sender].add(calcDay());

        uint256 volume = routerContract.getAmountsIn(amountOut, path)[0];
        require(msg.value >= volume, "Not enough balance!");

        if (lastAddedDay != totalDays) tradeRecorder(amountOut);
        if (msg.value > volume)
            payable(msg.sender).transfer(msg.value - volume);
        return
            routerContract.swapETHForExactTokens{value: volume}(
                amountOut,
                path,
                to,
                deadline
            );
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory) {
        if (
            !tradedDays[msg.sender].contains(calcDay()) && calcDay() < totalDays
        ) tradedDays[msg.sender].add(calcDay());

        require(
            tokenContract.allowance(msg.sender, address(this)) >= amountIn,
            "Not enough allowance!"
        );
        require(
            tokenContract.transferFrom(msg.sender, address(this), amountIn),
            "Unsuccesful token transfer!"
        );

        if (lastAddedDay != totalDays) tradeRecorder(amountIn);
        return
            routerContract.swapExactTokensForETH(
                amountIn,
                amountOutMin,
                path,
                to,
                deadline
            );
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory out) {
        if (
            !tradedDays[msg.sender].contains(calcDay()) && calcDay() < totalDays
        ) tradedDays[msg.sender].add(calcDay());
        require(
            tokenContract.allowance(msg.sender, address(this)) >= amountInMax,
            "Not enough allowance!"
        );

        require(
            tokenContract.transferFrom(
                msg.sender,
                address(this),
                routerContract.getAmountsIn(amountOut, path)[0]
            )
        );

        out = routerContract.swapTokensForExactETH(
            amountOut,
            amountInMax,
            path,
            to,
            deadline
        );
        if (lastAddedDay != totalDays) tradeRecorder(out[0]);
    }

    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts){
        return routerContract.getAmountsOut(amountIn, path);
    }
    
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts){
        return routerContract.getAmountsIn(amountOut, path);
    }
}

// bölü 0 ları engelle

//TODO: Muldiv ve unchecked'ler ile çarpma işlemlerini daha güvenli hale getir
//https://xn--2-umb.com/21/muldiv/
//https://docs.soliditylang.org/en/v0.8.0/control-structures.html#checked-or-unchecked-arithmetic

//TODO: Make prettier looked
//https://docs.soliditylang.org/en/v0.8.7/style-guide.html

/*
    address[] memory path = new address[](2);
    path[0] = routerContract.WETH();
    path[1] = address(tokenContract);
*/