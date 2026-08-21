package Plugins::DSDTranscode::Log;

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
