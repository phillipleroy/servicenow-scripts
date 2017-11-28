#need to fills command from environment 
if (test-path env:\SNC_accessKey) {
  $accessKey=$env:SNC_accessKey;
  $secretKey=$env:SNC_secretKey;
  $sessionToken=$env:SNC_sessionToken;
  $source=$env:SNC_source;
  $target=$env:SNC_target;
  $recursive=$env:SNC_recursive;
  $exclude=$env:SNC_exclude;
  $include=$env:SNC_include;
  $region=$env:SNC_region;
  $secondsToWait=$env:SNC_secondsToWait;
};


$cmd='SET AWS_ACCESS_KEY_ID=' + $accessKey + '& '
$cmd= $cmd + 'SET AWS_SECRET_ACCESS_KEY=' + $secretKey + '& '
if ($sessionToken){
	$cmd = $cmd + 'SET AWS_SESSION_TOKEN=' + $sessionToken + '& '
}

$options= ' --region "' + $region +'"';

if ( $recursive ){
   $options = $options + " --recursive ";
}

if ( $exclude){
    $options = $options + '  --exclude "' + $exclude + '"';
}
		
if ( $include ){
    $options = $options + '  --include "' + $include + '"';
}

$cmd=$cmd + 'aws s3 cp '+ $options+' "'+ $source + '" "' + $target + '" '

launchProcess  -computer $computer -cred $cred -command "$cmd" -secondsToWait $secondsToWait