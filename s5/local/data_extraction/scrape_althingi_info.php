<meta charset = "utf-8" />
<?php
/*
Author: Judy Fong, Inga Rún, Háskólinn í Reykjavík;
Description: The script extracts info on where to find audio file segments and corresponding
xml files on the althingi website and saves it to the AlthingiUploads dir using cURL;
*/
$outpath=$argv[1];
$start=$argv[2];
$stop=$argv[3];
for($i = $start; $i <= $stop; $i++){
    $ch = curl_init('http://www.althingi.is/altext/xml/raedulisti/?lthing=' . $i);
    $info_file_name = $outpath . $i . '.txt';
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
    //curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, 1);
    //curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 1);
    curl_setopt($ch, CURLOPT_USERAGENT, 'Mozilla/5.0 (compatible; Chrome/22.0.1216.0)');
    curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
    $output = curl_exec($ch);
    if(curl_exec($ch) == false)
    {
        echo 'Curl error: ' . curl_error($ch);
    }
    else
    {
        echo "Operation completed without any cURL errors\n";
    }
    $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($status == 200) {
        file_put_contents($info_file_name, $output);
    }
    else
    {
	echo 'status is what?! ' . $status . "\n";
	echo 'the output is a failure ' . $output . "\n";
    }
}
?>