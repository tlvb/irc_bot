use warnings;
use strict;
use IO::Socket::SSL;
use IRC_Bot::IRC_IO;
use IRC_Bot::IRC_Basics;
use IRC_Bot::PluginManager;

my $staying_alive = 1;

die 'needs config file as parameter' unless @ARGV == 1;
my $config = $ARGV[0];
open my $fh, '<', $ARGV[0] or die $!;
my %opt = ();
for (<$fh>) {
	chomp;
	my ($k, $v) = split /\s*=\s*/, $_, 2;
	$opt{$k} = $v;
}
close $fh;
my $ssl = $opt{ssl} or 0;
my $host = $opt{host} or die 'no host in config file';
my $port = $opt{port} or die 'no port in config file';
my $user = $opt{user} or die 'no user in config file';
my $nick = $opt{nick} or die 'no nick in config file';
my $password = $opt{password} or die 'no password in config file';
my $channel = $opt{channel} or die 'no channel in config file';
my @plugins = split /\s*,\s*/, ($opt{plugins}//'');
my $pdir = $opt{persistence_dir} // '/tmp';

my $plugman = IRC_Bot::PluginManager->new($pdir);
for (@plugins) {
	$plugman->try_load_plugin($_);
}
my $recon_delay = 0;
while ($staying_alive) {
	my $ircio = IRC_Bot::IRC_IO->new(ssl=>$ssl);
	my $irc = IRC_Bot::IRC_Basics->new($ircio);
	$SIG{INT} = sub {
		$ircio->csend('QUIT', 'SIGINT');
		$staying_alive = 0;
	};
	$SIG{QUIT} = sub {
		$ircio->csend('QUIT', 'SIGQUIT');
		$staying_alive = 0;
		$ircio->close();
	};
	my $ok = 0;
	$ircio->connect($host, $port);
	if ($ircio->is_connected()) {
		$recon_delay = 0;
		my $ret = $irc->init_plain_sasl_auth($user, $password);
		if ($ret == 0) {
			$ret = $irc->init_nick_and_ghost($nick);
			if ($ret == 0) {
				$ok = 1;
			}
		}
		$ircio->csend('JOIN', $channel) if $ok;
	}
	while ($ok and $ircio->is_connected()) {
		while (my $m = $irc->wait_for_input(60)) {
			if (exists $m->{ERROR}) {
				$ok = 0;
				last;
			}
			else {
				my @res = $plugman->distribute($nick, $m);
				my $counter = 0;
				for (@res) {
					if (++$counter == 3) {
						$counter = 0;
						sleep 2;
					}
					eval {
						$ircio->csend(@{$_});
					};
					sleep 0.5;
				}
			}
		}
	}
	$ircio->close();
	if ($recon_delay == 0) {
		$recon_delay = 1;
	}
	else {
		print "sleeping $recon_delay seconds before attempting to reconnect\n";
		sleep $recon_delay;
		if ($recon_delay < 128) {
			$recon_delay *= 2;
		}
	}
}

$plugman->try_unload_all_plugins();
