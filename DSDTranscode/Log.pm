package Plugins::DSDTranscode::Log;

# Central log category for the plugin. addLogCategory() registers the
# category with LMS so it can be tuned under
# Settings -> Advanced -> Logging; the description is a strings.txt key.

use strict;
use warnings;

use Slim::Utils::Log;

my $log;

sub get {
	unless ($log) {
		$log = Slim::Utils::Log->addLogCategory({
			'category'     => 'plugin.dsdtranscode',
			'defaultLevel' => 'WARN',
			'description'  => 'PLUGIN_DSDTRANSCODE',
		});
	}
	return $log;
}

1;
