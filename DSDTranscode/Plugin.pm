package Plugins::DSDTranscode::Plugin;

# DSD to PCM Transcoding plugin for Lyrion Music Server
#

use strict;
use warnings;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Control::Request;
use Slim::Player::Client;

use Plugins::DSDTranscode::TranscodingRules;
use Plugins::DSDTranscode::Settings;
use Plugins::DSDTranscode::Settings::Player;

our $VERSION = '1.0.1';

# Registers the 'plugin.dsdtranscode' log category. addLogCategory()
# returns a usable logger handle in current LMS - same idiom as most
# third-party plugins.
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.dsdtranscode',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_DSDTRANSCODE',
});

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

	# Register both settings pages. Slim::Web::Settings::new() 
	# inspects needsClient() itself to decide whether this
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
