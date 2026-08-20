package Plugins::DSDTranscode::Settings::Player;

# Per-player settings page: Settings -> Player -> [DSD to PCM Transcoding]
#
# Structure and handler pattern copied directly from the confirmed-working
# QueueConsume::PlayerSettings.pm: manual prefs get/set, SUPER::handler()
# called last purely for page chrome. validFor() combines isPlayer() (the
# check the working reference uses) with our own model check, since our
# transcoding rule is genuinely squeezelite-specific (unlike QueueConsume,
# which works for any player).

use strict;
use warnings;

use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

use Plugins::DSDTranscode::TranscodingRules;

my $prefs = preferences('plugin.dsdtranscode');

sub name        { 'PLUGIN_DSDTRANSCODE_PLAYER' }
sub page        { 'plugins/DSDTranscode/settings/player.html' }
sub needsClient { 1 }

sub validFor {
	my ($class, $client) = @_;
	return unless $client;
	return $client->isPlayer() && eval { $client->model eq 'squeezelite' };
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	my $cprefs = $prefs->client($client);

	if ($paramRef->{saveSettings}) {
		$cprefs->set('rateOverride', $paramRef->{pref_rateOverride});
		$cprefs->set('gainOverride', $paramRef->{pref_gainOverride});

		Plugins::DSDTranscode::TranscodingRules::rebuildFor($client);
	}

	$paramRef->{prefs}{pref_rateOverride} = $cprefs->get('rateOverride');
	$paramRef->{prefs}{pref_gainOverride} = $cprefs->get('gainOverride');

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
