package Plugins::DSDTranscode::Settings;

# Server-wide settings page: Settings -> [DSD to PCM Transcoding]
#
# Handler pattern mirrors the confirmed-working QueueConsume plugin's
# PlayerSettings.pm: read/write prefs manually, populate
# $paramRef->{prefs}{pref_X} ourselves, and call SUPER::handler() last,
# purely for the page chrome (topLevelItems / orderedLinks / template
# rendering) - not relying on the base class's prefs()-driven generic
# loop.

use strict;
use warnings;

use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Player::Client;

use Plugins::DSDTranscode::TranscodingRules;

my $prefs = preferences('plugin.dsdtranscode');

sub name        { 'PLUGIN_DSDTRANSCODE' }
sub page        { 'plugins/DSDTranscode/settings/basic.html' }
sub needsClient { 0 }

sub handler {
	my ($class, $client, $paramRef) = @_;

	if ($paramRef->{saveSettings}) {
		$prefs->set('enabled',          $paramRef->{pref_enabled}          ? 1 : 0);
		$prefs->set('disableNativeDSD', $paramRef->{pref_disableNativeDSD} ? 1 : 0);
		$prefs->set('defaultRate',      $paramRef->{pref_defaultRate});
		$prefs->set('gain',             $paramRef->{pref_gain});

		Plugins::DSDTranscode::TranscodingRules::init();

		# server-wide values changed - re-resolve every connected player
		# in case any of them are still using the model-wide default.
		for my $c (Slim::Player::Client::clients()) {
			Plugins::DSDTranscode::TranscodingRules::rebuildFor($c);
		}
	}

	$paramRef->{prefs}{pref_enabled}          = $prefs->get('enabled');
	$paramRef->{prefs}{pref_disableNativeDSD} = $prefs->get('disableNativeDSD');
	$paramRef->{prefs}{pref_defaultRate}      = $prefs->get('defaultRate');
	$paramRef->{prefs}{pref_gain}             = $prefs->get('gain');

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
