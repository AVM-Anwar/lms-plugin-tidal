package Plugins::TIDAL::Plugin;

use strict;

use base qw(Slim::Plugin::OPMLBased);

# use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);

use Plugins::TIDAL::API::Async;
use Plugins::TIDAL::ProtocolHandler;

my $log = Slim::Utils::Log->addLogCategory({
	'category'    => 'plugin.tidal',
	'description' => 'PLUGIN_TIDAL_NAME',
});

my $prefs = preferences('plugin.tidal');

sub initPlugin {
	my $class = shift;

	$prefs->init({
		quality => 'HIGH',
	});

	Plugins::TIDAL::API::Async->init();

	if (main::WEBUI) {
		require Plugins::TIDAL::Settings;
		require Plugins::TIDAL::Settings::Auth;
		Plugins::TIDAL::Settings->new();
		Plugins::TIDAL::Settings::Auth->new();
	}

	Slim::Player::ProtocolHandlers->registerHandler('tidal', 'Plugins::TIDAL::ProtocolHandler');

	$class->SUPER::initPlugin(
		feed   => \&handleFeed,
		tag    => 'tidal',
		menu   => 'apps',
		is_app => 1,
	);
}

# TODO - check for account, allow account selection etc.
sub handleFeed {
	my ($client, $cb, $args) = @_;
	my $items = [{
		name  => cstring($client, 'SEARCH'),
		image => 'html/images/search.png',
		type => 'link',
		url  => \&getSearches,
	},{
		name  => cstring($client, 'GENRES'),
		image => 'html/images/genres.png',
		type => 'link',
		url  => \&getGenres,
	} ];

	# TODO - more menu items...

	$cb->({ items => $items });
}

sub getSearches {
	my ( $client, $callback, $args ) = @_;
	my $menu = [];

	$menu = [ {
		name => cstring($client, 'EVERYTHING'),
		type  => 'search',
		url   => \&search,
	}, {
		name => cstring($client, 'PLAYLISTS'),
		type  => 'search',
		url   => \&search,
		passthrough => [ { type => 'playlists'	} ],
	}, {
		name => cstring($client, 'ARTISTS'),
		type  => 'search',
		url   => \&search,
		passthrough => [ { type => 'artists' } ],
	}, {
		name => cstring($client, 'ALBUMS'),
		type  => 'search',
		url   => \&search,
		passthrough => [ { type => 'albums' } ],
	}, {
		name => cstring($client, 'TRACKS'),
		type  => 'search',
		url   => \&search,
		passthrough => [ { type => 'tracks' } ],
	} ];

	$callback->( { items => $menu } );
	return;
}

sub getAlbum {
	my ( $client, $cb, $args, $params ) = @_;

	getAPIHandler($client)->albumTracks(sub {
		my $items = _renderTracks(shift);
		$cb->( {
			items => $items
		} );
	}, $params->{id});
}

sub getGenres {
	my ( $client, $callback ) = @_;

	getAPIHandler($client)->genres(sub {
		my $items = [ map { {
			name => $_->{name},
			type => 'outline',
			items => [ {
				name => cstring($client, 'PLAYLISTS'),
				type  => 'link',
				url   => \&getGenreItems,
				passthrough => [ { genre => $_->{path}, type => 'playlists' } ],
			}, {
				name => cstring($client, 'ALBUMS'),
				type  => 'link',
				url   => \&getGenreItems,
				passthrough => [ { genre => $_->{path}, type => 'albums' } ],
			}, {
				name => cstring($client, 'TRACKS'),
				type  => 'link',
				url   => \&getGenreItems,
				passthrough => [ { genre => $_->{path}, type => 'tracks' } ],
			} ],
			image => Plugins::TIDAL::API->getImageUrl($_, 'genre'),
			passthrough => [ { genre => $_->{path} } ],
		} } @{$_[0]} ];

		$callback->( { items => $items } );
	});
}

sub getGenreItems {
	my ( $client, $cb, $args, $params ) = @_;
	getAPIHandler($client)->genreByType(sub {
		my $items = [ map { _renderItem($_) } @{$_[0]} ];

		$cb->( {
			items => $items
		} );
	}, $params->{genre}, $params->{type} );
}

sub getPlaylist {
	my ( $client, $cb, $args, $params ) = @_;
	getAPIHandler($client)->playlist(sub {
		my $items = _renderTracks(shift);
		$cb->( {
			items => $items
		} );
	}, $params->{uuid} );
}

sub search {
	my ($client, $cb, $args, $params) = @_;

	$args->{search} ||= $params->{query};
	$args->{type} = "/$params->{type}";

	getAPIHandler($client)->search(sub {
		my $items = shift;
		$items = [ map { _renderItem($_) } @$items ] if $items;

		$cb->( {
			items => $items || []
		} );
	}, $args);

}

sub _renderItem {
	my ($item) = @_;

	my $type = Plugins::TIDAL::API->typeOfItem($item);

	if ($type eq 'track') {
		return _renderTrack($item);
	}
	elsif ($type eq 'album') {
		return _renderAlbum($item);
	}
	elsif ($type eq 'artist') {
		return _renderArtist($item);
	}
	elsif ($type eq 'playlist') {
		return _renderPlaylist($item);
	}
}

sub _renderPlaylists {
	my $results = shift;

	return [ map {
		_renderPlaylist($_)
	} @{$results->{items}}];
}

sub _renderPlaylist {
	my $item = shift;

	return {
		name => $item->{title},
		line1 => $item->{title},
		line2 => join(', ', map { $_->{name} } @{$item->{promotedArtists} || []}),
		type => 'playlist',
		url => \&getPlaylist,
		image => Plugins::TIDAL::API->getImageUrl($item),
		passthrough => [ { uuid => $item->{uuid} } ],
	};
}

sub _renderAlbums {
	my $results = shift;

	return [ map {
		_renderAlbum($_);
	} @{$results->{items}} ];
}

sub _renderAlbum {
	my $item = shift;

	return {
		name => $item->{title},
		line1 => $item->{title},
		line2 => $item->{artist}->{name},
		type => 'playlist',
		url => \&getAlbum,
		image => Plugins::TIDAL::API->getImageUrl($item),
		passthrough => [{ id => $item->{id} }],
	};
}

sub _renderTracks {
	my $tracks = shift;

	return [ map {
		_renderTrack($_);
	} @$tracks ];
}

sub _renderTrack {
	my $item = shift;

	return {
		name => $item->{title},
		line1 => $item->{title},
		line2 => $item->{artist},
		on_select => 'play',
		play => "tidal://$item->{id}." . Plugins::TIDAL::ProtocolHandler::getFormat(),
		playall => 1,
		image => $item->{cover},
	};
}

sub _renderArtists {
	my $results = shift;

	return [ map {
		_renderArtist($_);
	} @{$results->{items}} ];
}

sub _renderArtist {
	my $item = shift;

	return {
		name => $item->{name},
		url => \&getArtist,
		type => 'link',
		image => Plugins::TIDAL::API->getImageUrl($item),
		passthrough => [{ id => $item->{id} }],
	};
}

sub getAPIHandler {
	my ($client) = @_;

	my $api;

	if (ref $client) {
		$api = $client->pluginData('api');

		if ( !$api ) {
			# if there's no account assigned to the player, just pick one
			if ( !$prefs->client($client)->get('userId') ) {
				my $userId = Plugins::TIDAL::API->getSomeUserId();
				$prefs->client($client)->set('userId', $userId) if $userId;
			}

			$api = $client->pluginData( api => Plugins::TIDAL::API::Async->new({
				client => $client
			}) );
		}
	}
	else {
		$api = Plugins::TIDAL::API::Async->new({
			userId => Plugins::TIDAL::API->getSomeUserId()
		});
	}

	logBacktrace("Failed to get a TIDAL API instance: $client") unless $api;

	return $api;
}

1;