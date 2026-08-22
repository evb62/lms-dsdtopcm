package Plugins::DSDTranscode::Settings;

# Server-wide settings page (Settings -> Plugins -> DSD to PCM Transcoding).
#
# Preferences are read/written manually and exposed to the template as
# $paramRef->{prefs}{pref_*} instead of relying on the base class's prefs()
# list; SUPER::handler() is called last purely for the page chrome
# (settings menu, template rendering).

use strict;
use warnings;

use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Player::Client;

use Plugins::DSDTranscode::TranscodingRules;

my $prefs = preferences('plugin.dsdtranscode');

# name/page/needsClient define how the page is registered:
#   - page is the URL below /plugins/... and must match the template path
#     relative to HTML/EN (i.e. HTML/EN/plugins/DSDTranscode/settings/basic.html).
#   - needsClient() = 0 makes this a server-wide page. install.xml's
#     <optionsURL> points at the same URL, which is what puts the "Settings"
#     link into the Manage Plugins list.
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

		# Server-wide values changed: reinstall the rules and re-resolve
		# every connected player in case any of them was using the default.
		Plugins::DSDTranscode::TranscodingRules::init();

		for my $c (Slim::Player::Client::clients()) {
			Plugins::DSDTranscode::TranscodingRules::rebuildFor($c);
		}
	}

	# Populate the form with the current values.
	$paramRef->{prefs}{pref_enabled}          = $prefs->get('enabled');
	$paramRef->{prefs}{pref_disableNativeDSD} = $prefs->get('disableNativeDSD');
	$paramRef->{prefs}{pref_defaultRate}      = $prefs->get('defaultRate');
	$paramRef->{prefs}{pref_gain}             = $prefs->get('gain');

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
