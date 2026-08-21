package Plugins::DSDTranscode::Plugin;

# DSD to PCM Transcoding plugin for Lyrion Music Server
#
# Automates the three changes described in the original DSD -> PCM
# transcoding guide:
#   A. Disables the native wvpx->dsf / wvpx->dff routes so DSD/DoP can
#      never reach a player.
#   B. (left to the player's own config, see README - optional once A is in place)
#   C. Installs a wvpx->flc conversion rule with a pinned output sample
#      rate, server-wide by default, with an optional per-player override.
#
# NOTE ON VERIFICATION: the pieces marked "confirmed" in the comments
# below were checked directly against TranscodingHelper.pm,
# CapabilitiesHelper.pm, PluginManager.pm, Client.pm and Settings.pm from
# the slimserver source. Slim::Plugin::Base's exact initPlugin/getDisplayName
# contract was NOT independently re-derived from source in this session -
# it follows the extremely common convention seen across third-party LMS
# plugins, but is worth a quick sanity check against another installed
# plugin's Plugin.pm if initPlugin doesn't fire as expected.

use strict;
use warnings;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Control::Request;
use Slim::Player::Client;

use Plugins::DSDTranscode::Log;
use Plugins::DSDTranscode::TranscodingRules;
use Plugins::DSDTranscode::Settings;
use Plugins::DSDTranscode::Settings::Player;

my $log = Plugins::DSDTranscode::Log::get();

our $VERSION = '1.0.3';

# preferences('server') and $prefs->client($client) are confirmed patterns -
# both are used this exact way inside TranscodingHelper.pm and Client.pm.
my $prefs = preferences('plugin.dsdtranscode');

$prefs->init({
	enabled          => 1,      # master switch - the plugin's own rollback lever
	disableNativeDSD => 1,      # Part A: block wvpx->dsf / wvpx->dff
	defaultRate      => 88200,  # Part C default, Hz - 88200 / 176400 / 352800
	gain             => -3,     # dB of headroom, see guide 8.5
});

sub getDisplayName { 'PLUGIN_DSDTRANSCODE' }

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(@_);

	# Register both settings pages. Slim::Web::Settings::new() (confirmed
	# in Settings.pm) inspects needsClient() itself to decide whether this
	# becomes a server-wide link or a per-player settings page - nothing
	# else to wire up here. main::WEBUI guard matches the confirmed-working
	# QueueConsume plugin's own initPlugin().
	if (main::WEBUI) {
		Plugins::DSDTranscode::Settings->new;
		Plugins::DSDTranscode::Settings::Player->new;
	}

	# Install/refresh the server-wide default profile and the
	# disabledformats entries.
	Plugins::DSDTranscode::TranscodingRules::init();

	# Apply to every player already connected when the plugin (re)loads -
	# covers a server restart with players already online.
	for my $client (Slim::Player::Client::clients()) {
		Plugins::DSDTranscode::TranscodingRules::rebuildFor($client);
	}

	# ['client'],['new'] is confirmed: Client::new() calls
	# Slim::Control::Request::notifyFromArray($client, ['client','new'])
	# at the end of construction. 'reconnect' is included defensively for
	# a player that drops and comes back with the same id - remove it if
	# it turns out not to fire the same handler shape.
	Slim::Control::Request::subscribe(
		\&_onClientNew,
		[ ['client'], ['new', 'reconnect'] ],
	);

	main::INFOLOG && $log->is_info && $log->info('DSDTranscode initialized');
}

sub _onClientNew {
	my $request = shift;
	my $client  = $request->client || return;

	Plugins::DSDTranscode::TranscodingRules::rebuildFor($client);
}

# Best-effort cleanup on removal. NOT CONFIRMED against source whether
# PluginManager actually calls shutdownPlugin() before an uninstall (as
# opposed to only on a plain disable, or not at all before rmtree) - this
# is a safety net, not something to rely on. The real defense is manual:
# uncheck "Enable DSD transcoding" on the settings page and restart
# *before* removing the plugin, so init()'s own disable path (already
# tested and confirmed working) restores everything cleanly first. If
# that step gets skipped, native DSD/DoP playback will stay broken after
# removal until wvpx->dsf / wvpx->dff are manually re-enabled on
# Settings -> Advanced -> File Types, regardless of whether this hook
# fires.
sub shutdownPlugin {
	Plugins::DSDTranscode::TranscodingRules::teardown();
}

1;

__END__
