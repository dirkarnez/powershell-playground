# 將待處理工作用 PSCustomObject 包成物件
# 包含參數及分組代碼及存放結果用的屬性
# 註: Class 要 PS 5.1+，為相容 PS 4.0 可取 PSCustomObject
$todo = 1..100 | ForEach-Object { 
    return [PSCustomObject]@{
        Name   = "Job - $_"
        GrpNo  = -1
        Result = ""
    }
} 

# 在 PowerShell 要搞非同步鎖定有點困難，就不搞待處理 Queue 或消費者生產者模型了
# 用以下函式事先將待處理陣列平分成多個
function SplitArray([object[]]$array, [int]$groupCount) {
    $arrayLength = $array.Length;
    # 注意：C# 整數相除結果為無條件捨去的整數，但 PowerShell 則含小數點
    $countPerGrp = [Math]::Floor($arrayLength / $groupCount)
    $remainder = $arrayLength % $groupCount
    $result = New-Object System.Collections.ArrayList
    $index = 0
    0..($groupCount - 1) | ForEach-Object {
        $takeCount = $countPerGrp
        if ($_ -le $remainder - 1) {
            # 除不盡的餘數由前面幾筆分攤
            $takeCount++
        }
        # 用 Skip + First 從第 index 取 takeCount 筆進行分組
        $subArray = @($array | Select-Object -Skip $index -First $takeCount)
        # 在待處理工作項目標註群組別(這個是實驗觀察用的，實務應用時不需要)
        $subArray.ForEach("GrpNo", $_)
        $index += $takeCount
        $result.Add($subArray)
    } | Out-Null
    return $result
}

# 將待處理項目分成八組
$groups = SplitArray $todo 8

$sw = New-Object System.Diagnostics.Stopwatch
$sw.Start()
# 平行執行
$psJobPool = New-Object System.Collections.ArrayList
$groups | ForEach-Object {
    $psJob = Start-Job -ScriptBlock {
        param ([object[]]$array)
        $array | ForEach-Object {
            $randNum = 1
            $_.Result = $randNum
            # 填上執行結果後將整個 PSCustomObject 回傳
            return $_
        }
        # 眉角：下寫的寫法確保將整個 ArrayList 當成 ArgumentList 的一個參數
        #       而非將 ArrayList 轉成 ArgumentList
        #       參考：https://blog.darkthread.net/blog/psfaq-return-collection/
    } -ArgumentList @(, $_) 
    $psJobPool.Add($psJob) | Out-Null
}
# Wait-Job 可等待所有 PSJob 結束
$psJobPool | Wait-Job | Out-Null
$sw.Stop()
# Receive-Job 接收 PSJob 傳回結果
$result = $psJobPool | Receive-Job
$result | ForEach-Object {
    Write-Host "[$($_.GrpNo)] $($_.Name) : $($_.Result)"
}
Write-Host "Spent $([TimeSpan]::FromMilliseconds($sw.ElapsedMilliseconds)) seconds"