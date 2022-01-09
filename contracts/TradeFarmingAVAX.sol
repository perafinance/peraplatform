//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
/* 
    DEX'lerdeki swap fonksiyonlarını ve kullandığım lib'leri interface'e ekledim
    Tüm Uniswap v2 forku dexler ile uyumlu çalışacak durumdayız -> yani Avalanche'ta hepsi
*/
import "./interfaces/IPangolinRouter.sol";
/*
    ERC-20 Interface'i
    Swap ve ödül tokenlarında kullanılacak
*/
import "./interfaces/IERC20.sol";

// çalışacak olan trade farming kontratı bu kısım. sonrasında bir factory kontratın bu kontratı üreteceği bir yapıya geçeceğiz
// bu örnek AVAX-token çiftleri için token cinsinden hacim takip ederek yarışma düzenliyor
contract TradeFarming is Ownable {
    using EnumerableSet for EnumerableSet.UintSet; // kullanıcıların trade ettiği günleri tutacağımız set

    uint256 private immutable deployTime; // yarışma başlama anı timestampi
    IPangolinRouter routerContract; // router instanceımız
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
    uint256 constant PRECISION = 1_000_000_000;

    constructor(
        address _routerAddress,
        address _tokenAddress,
        address _rewardAddress,
        uint256 _previousVolume,
        uint256 _previousDay,
        uint256 _totalDays
    ) {
        deployTime = block.timestamp;
        routerContract = IPangolinRouter(_routerAddress);
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
        return muldiv(dailyVolumes[_day], PRECISION, previousVolumes[_day]);
    }

    /*
        fonksiyon en son hacim hesaplaması yapılan günün ertesi gününün hacmini de hesaplayarak ortalamaya ekler
    */
    function addNextDaysToAverage() private {
        uint256 _cd = calcDay();
        uint256 _pd = previousDay + lastAddedDay + 1;
        require(lastAddedDay + 1 <= _cd, "Not ready to operate!");
        previousVolumes[lastAddedDay + 1] =
            muldiv(previousVolumes[lastAddedDay], (_pd - 1), _pd) +
            dailyVolumes[lastAddedDay] /
            _pd;

        /*
            Günlük ödül = (ödül havuzunda kalan miktar / kalan gün) * hacmin önceki güne göre değişimi
            %10 ödül değişim sınırı var
            Swap yoksa ödül yok
        */

        // Hacim değişimlerini %90 - %110 arasında kısıtlıyoruz
        uint256 volumeChange = calculateDayVolumeChange(lastAddedDay);
        if (volumeChange > 1_100_000_000) {
            volumeChange = 1_100_000_000;
        } else if (volumeChange < 900_000_000) {
            volumeChange = 900_000_000;
        }

        dailyRewards[lastAddedDay] = muldiv(
            (totalRewardBalance / (totalDays - lastAddedDay)),
            volumeChange,
            PRECISION
        );
        totalRewardBalance = totalRewardBalance - dailyRewards[lastAddedDay];

        lastAddedDay += 1;

        if (lastAddedDay + 1 <= _cd && lastAddedDay != totalDays)
            addNextDaysToAverage();
    }

    // Mevcut gün hariç tüm günlere ait ödülleri claim et
    function claimAllRewards() external {
        // Önce tüm hacim hesaplamaları güncel mi kontrol edilir
        if (lastAddedDay + 1 <= calcDay() && lastAddedDay != totalDays) {
            addNextDaysToAverage();
        }

        uint256 totalRewardOfUser = 0;
        uint256 rewardRate = PRECISION;
        for (uint256 i = 0; i < tradedDays[msg.sender].length(); i++) {
            if (tradedDays[msg.sender].at(i) < lastAddedDay) {
                // FIXME: Test1 de arrayin son değeri buraya girmiyor
                rewardRate = muldiv(
                    volumeRecords[msg.sender][tradedDays[msg.sender].at(i)],
                    PRECISION,
                    dailyVolumes[tradedDays[msg.sender].at(i)]
                );
                totalRewardOfUser += muldiv(
                    rewardRate,
                    dailyRewards[tradedDays[msg.sender].at(i)],
                    PRECISION
                );
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
        uint256 rewardRate = PRECISION;
        for (uint256 i = 0; i < tradedDays[msg.sender].length(); i++) {
            if (tradedDays[msg.sender].at(i) < lastAddedDay) {
                rewardRate = muldiv(
                    volumeRecords[msg.sender][tradedDays[msg.sender].at(i)],
                    PRECISION,
                    dailyVolumes[tradedDays[msg.sender].at(i)]
                );
                totalRewardOfUser += muldiv(
                    rewardRate,
                    dailyRewards[tradedDays[msg.sender].at(i)],
                    PRECISION
                );
            }
        }
        return totalRewardOfUser;
    }

    // Bir kullanıcının belirtilen gündeki ödülünü döner
    function calculateDailyUserReward(uint256 _day)
        external
        view
        returns (uint256)
    {
        uint256 rewardOfUser = 0;
        uint256 rewardRate = PRECISION;
        if (_day < lastAddedDay && tradedDays[msg.sender].contains(_day)) {
            rewardRate = muldiv(
                volumeRecords[msg.sender][_day],
                PRECISION,
                dailyVolumes[_day]
            );
            rewardOfUser += muldiv(rewardRate, dailyRewards[_day], PRECISION);
        }
        return rewardOfUser;
    }

    // Ödülleri hesaplanmamış bir gün olup olmadığını döner
    function isCalculated() external view returns (bool) {
        return (!(lastAddedDay + 1 <= calcDay() && lastAddedDay != totalDays) ||
            lastAddedDay == totalDays);
    }

    function swapExactAVAXForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory out) {
        if (
            !tradedDays[msg.sender].contains(calcDay()) && calcDay() < totalDays
        ) tradedDays[msg.sender].add(calcDay());
        require(msg.value > 0, "Not enough balance!");

        out = routerContract.swapExactAVAXForTokens{value: msg.value}(
            amountOutMin,
            path,
            to,
            deadline
        );
        if (lastAddedDay != totalDays) tradeRecorder(out[out.length - 1]);
    }

    function swapAVAXForExactTokens(
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
            routerContract.swapAVAXForExactTokens{value: volume}(
                amountOut,
                path,
                to,
                deadline
            );
    }

    function swapExactTokensForAVAX(
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
            routerContract.swapExactTokensForAVAX(
                amountIn,
                amountOutMin,
                path,
                to,
                deadline
            );
    }

    function swapTokensForExactAVAX(
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

        out = routerContract.swapTokensForExactAVAX(
            amountOut,
            amountInMax,
            path,
            to,
            deadline
        );
        if (lastAddedDay != totalDays) tradeRecorder(out[0]);
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts)
    {
        return routerContract.getAmountsOut(amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts)
    {
        return routerContract.getAmountsIn(amountOut, path);
    }

    /**
        @dev Remco Bloemen's muldiv function https://2π.com/21/muldiv/
        @dev Reasons why we use it:
            1. it is cheap on gas
            2. it doesn't revert where (a*b) overflows and (a*b)/c doesn't
    */
    function muldiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) private pure returns (uint256 result) {
        require(denominator > 0);

        uint256 prod0;
        uint256 prod1;
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        if (prod1 == 0) {
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }
        require(prod1 < denominator);
        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        uint256 twos = denominator & (~denominator + 1);
        assembly {
            denominator := div(denominator, twos)
        }

        assembly {
            prod0 := div(prod0, twos)
        }

        assembly {
            twos := add(div(sub(0, twos), twos), 1)
        }
        prod0 |= prod1 * twos;

        uint256 inv = (3 * denominator) ^ 2;

        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;

        result = prod0 * inv;
        return result;
    }
}

//TODO: Make prettier looked
//https://docs.soliditylang.org/en/v0.8.7/style-guide.html