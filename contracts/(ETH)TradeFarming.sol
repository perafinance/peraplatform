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

    mapping(uint256 => uint256) private previousVolumes; // belirtilen günden önceki günlerin hacim ortalaması kaç
    uint256 private previousDay; // yarışma başlamadan önce kaç günlük hacim ortalaması verisi dahil edildi
    uint256 private lastAddedDay = 0; // en son hangi günde önceki günün ortalama hesabı yapıldı
    uint256 private totalRewardBalance = 0; // dağıtılmamış toplam ödül havuzu miktarı
    uint256 private totalDays;

    mapping(address => mapping(uint256 => uint256)) public volumeRecords; // kullanıcıların yarışma günlerine ait hacimleri
    mapping(uint256 => uint256) public dailyVolumes; // günlük toplam hacimler
    mapping(uint256 => uint256) public dailyRewards; // günlük ödüller

    mapping(address => EnumerableSet.UintSet) tradedDays; // kullanıcıların yarıştığı günler

    uint256 constant MAX_UINT = 2**256 - 1;

    constructor() {
        deployTime = block.timestamp;
        routerContract = IUniswapV2Router01(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        tokenContract = IERC20(0xc7AD46e0b8a400Bb3C915120d284AafbA8fc4735);
        rewardToken = IERC20(0xc7AD46e0b8a400Bb3C915120d284AafbA8fc4735);
        previousVolumes[0] = 5000000000;
        previousDay = 5;
        tokenContract.approve(address(routerContract), MAX_UINT);
        rewardToken.approve(owner(), MAX_UINT);
        totalDays = 48;
    }

    // Ödül havuzuna (kontratın kendisi) token yatırmaya yarar
    function depositRewardTokens(uint256 amount) public onlyOwner {
        require(
            rewardToken.balanceOf(msg.sender) >= amount,
            "Not enough balance!"
        );
        require(
            rewardToken.allowance(msg.sender, address(this)) >= amount,
            "Not enough allowance!"
        );
        require(rewardToken.transferFrom(msg.sender, address(this), amount));
        totalRewardBalance = totalRewardBalance + amount;
    }

    // Ödül havuzundan (kontratın kendisi) token çekmeye yarar
    function withdrawRewardTokens(uint256 amount) public onlyOwner {
        require(
            rewardToken.balanceOf(address(this)) >= amount,
            "Not enough balance!"
        );
        require(rewardToken.transferFrom(address(this), msg.sender, amount));
        totalRewardBalance = totalRewardBalance - amount;
    }

    // Yarışmanın toplam süresini değiştirmeye yarar
    function changeTotalDays(uint256 _newTotalDays) public onlyOwner {
        totalDays = _newTotalDays;
    }

    /*
        Kaçıncı günde olduğumuzu hesaplayan fonksiyon
    */
    function calcDay() private view returns (uint256) {
        return (block.timestamp - deployTime) / 5 minutes;
    }

    /*
        Hacim kayıtlarını tutmak adına swap işleminden sonra çağıracağız
        Modifier olarak kullanmıştım. İptal
    */
    function tradeRecorder(uint256 _volume) private {
        volumeRecords[msg.sender][calcDay()] += _volume;
        dailyVolumes[calcDay()] += _volume;

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
        dailyRewards[lastAddedDay] =
            ((totalRewardBalance / (totalDays - lastAddedDay)) *
                calculateDayVolumeChange(lastAddedDay)) /
            1000;
        totalRewardBalance = totalRewardBalance - dailyRewards[lastAddedDay];
        lastAddedDay++;

        if (lastAddedDay + 1 <= _cd) addNextDaysToAverage();
    }

    // Mevcut gün hariç tüm günlere ait ödülleri claim et
    function claimAllRewards() public {
        // Önce tüm hacim hesaplamaları güncel mi kontrol edilir
        if (lastAddedDay + 1 <= calcDay()) {
            addNextDaysToAverage();
        }

        uint256 totalRewardOfUser = 0;
        uint256 rewardRate = 1000;
        for (uint256 i = 0; i < tradedDays[msg.sender].length(); i++) {
            if (tradedDays[msg.sender].at(i) < calcDay()) {
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
        require(
            tokenContract.transferFrom(
                address(this),
                msg.sender,
                totalRewardOfUser
            )
        );
    }

    // Sadece hesaplaması güncellenen günler için toplam ödülü döner
    function calculateUserRewards() external view returns (uint256) {
        uint256 totalRewardOfUser = 0;
        uint256 rewardRate = 1000;
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

    function TFswapExactETHForTokens(uint256 amountOutMin, uint256 deadline)
        external
        payable
        returns (uint256[] memory out)
    {
        if (!tradedDays[msg.sender].contains(calcDay()))
            tradedDays[msg.sender].add(calcDay());
        require(msg.value > 0, "Not enough balance!");

        address[] memory path = new address[](2);
        path[0] = routerContract.WETH();
        path[1] = address(tokenContract);

        out = routerContract.swapExactETHForTokens{value: msg.value}(
            amountOutMin,
            path,
            msg.sender,
            deadline
        );
        tradeRecorder(out[out.length - 1]);
    }

    function TFswapETHForExactTokens(uint256 amountOut, uint256 deadline)
        external
        payable
        returns (uint256[] memory)
    {
        if (!tradedDays[msg.sender].contains(calcDay()))
            tradedDays[msg.sender].add(calcDay());

        address[] memory path = new address[](2);
        path[0] = routerContract.WETH();
        path[1] = address(tokenContract);

        uint256 volume = routerContract.getAmountsIn(amountOut, path)[0];
        require(msg.value >= volume, "Not enough balance!");

        tradeRecorder(amountOut);
        if (msg.value > volume)
            payable(msg.sender).transfer(msg.value - volume);
        return
            routerContract.swapETHForExactTokens{value: volume}(
                amountOut,
                path,
                msg.sender,
                deadline
            );
    }

    function TFswapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline
    ) external returns (uint256[] memory) {
        if (!tradedDays[msg.sender].contains(calcDay()))
            tradedDays[msg.sender].add(calcDay());

        require(
            tokenContract.allowance(msg.sender, address(this)) >= amountIn,
            "Not enough allowance!"
        );
        require(
            tokenContract.transferFrom(msg.sender, address(this), amountIn),
            "Unsuccesful token transfer!"
        );

        address[] memory path = new address[](2);
        path[0] = address(tokenContract);
        path[1] = routerContract.WETH();

        tradeRecorder(amountIn);
        return
            routerContract.swapExactTokensForETH(
                amountIn,
                amountOutMin,
                path,
                msg.sender,
                deadline
            );
    }

    function TFswapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        uint256 deadline
    ) external returns (uint256[] memory out) {
        if (!tradedDays[msg.sender].contains(calcDay()))
            tradedDays[msg.sender].add(calcDay());
        require(
            tokenContract.allowance(msg.sender, address(this)) >= amountInMax,
            "Not enough allowance!"
        );

        address[] memory path = new address[](2);
        path[0] = address(tokenContract);
        path[1] = routerContract.WETH();
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
            msg.sender,
            deadline
        );
        tradeRecorder(out[0]);
    }
}
