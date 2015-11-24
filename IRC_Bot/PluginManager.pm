use warnings;
use strict;
package IRC_Bot::PluginManager;
use Storable;
use POSIX;

sub new { #{{{
	my ($class, $persistence_dir) = @_;
	$persistence_dir //= '/tmp';
	my $blocked = {};
	if (-f "$persistence_dir/PluginManager.storable.gz") {
		system '/usr/bin/gunzip', '-f', "$persistence_dir/PluginManager.storable.gz";
	}
	if (-f "$persistence_dir/PluginManager.storable") {
		$blocked = Storable::retrieve "$persistence_dir/PluginManager.storable";
	}
	my $self = {
		plugins=>{},
		persistence_dir=>$persistence_dir,
		blocked=>$blocked
	};
	print STDERR "current blocked names list:\n";
	for (keys %{$self->{blocked}}) {
		print STDERR "$_ until $self->{blocked}->{$_}\n";
	}
	print STDERR "end of current blocked names list\n";
	bless $self, $class;
	return $self;
} #}}}
sub add_plugin { #{{{
	my ($self, $plugin, $pluginfile) = @_[0..2];
	my $package = $_[3] // 'IRC_Bot::Plugins';
	require $pluginfile;
	my $newpi = "$package::$plugin"->new();
	$self->{plugins}->{$plugin} = $newpi;
} #}}}
sub remove_plugin { #{{{
	my ($self, $plugin, $pluginfile) = @_[0..2];
	delete $INC{$pluginfile} if exists $INC{$pluginfile};
	delete $self->{plugins}->{$plugin} if exists $self->{plugins}->{$plugin};
} #}}}
sub try_load_plugin { #{{{
	my ($self, $plugin) = @_;
	my $pluginfile = "IRC_Bot/Plugins/$plugin.pm";

	return 'INVALIDNAME' if $plugin =~ /[^a-zA-Z0-9_]/;
	return 'NOSUCHPLUGIN' unless -f $pluginfile;
	my $ret = '';

	if (grep {$_ eq $plugin} keys %{$self->{plugins}}) {
		my $ret = $self->try_unload_plugin($plugin, 1);
		return $ret if $ret ne '';
	}
	{
		local $@;
		eval {
			$self->add_plugin($plugin, $pluginfile);
			$self->load_plugin_state($plugin);
		};
		if ($@ ne '') {
			print "!!! ERROR\n---\n$@\n---\n";
			$self->remove_plugin($plugin, $pluginfile);
			return 'FAILEDLOAD';
		}
	}
	return '';
} #}}}
sub try_unload_plugin { #{{{
	my ($self, $plugin, $root) = @_;
	$root //= 0;

	return 'INVALIDNAME' if $plugin =~ /[^a-zA-Z0-9_]/;
	return 'NOTLOADED' unless grep {$_ eq $plugin} keys %{$self->{plugins}};
	return 'NOTPERMITTED' if (not $root) and (exists $self->{plugins}->{$plugin}->{protected}) and ($self->{plugins}->{$plugin}->{protected} != 0);

	my $pluginfile = "IRC_Bot/Plugins/$plugin.pm";
	{
		local $@;
		eval {
			$self->save_plugin_state($plugin);
		};
		if ($@ ne '') {
			print "!!! ERROR\n---\n$@\n---\n";
			return 'FAILEDSAVE';
		}
	}
	$self->remove_plugin($plugin, $pluginfile);
	return '';
} #}}}
sub load_plugin_state { #{{{
	my ($self, $plugin) = @_;
	my $pi = $self->{plugins}->{$plugin};
	my $dir = $self->{persistence_dir};
	if (defined $dir and -d $dir and $pi->can('load')) {
		if (-f "$dir/$plugin.storable.gz") {
			print "uncompressing $dir/$plugin.storable.gz\n";
			system '/usr/bin/gunzip', '-f', "$dir/$plugin.storable.gz";
		}
		if (-f "$dir/$plugin.storable") {
			print "loading $plugin data from $dir/$plugin.storable\n";
			my $data = Storable::retrieve "$dir/$plugin.storable";
			$pi->load($data);
		}
	}
} #}}}
sub save_plugin_state { #{{{
	my ($self, $plugin) = @_;
	my $pi = $self->{plugins}->{$plugin};
	my $dir = $self->{persistence_dir};
	if (defined $dir and $pi->can('save')) {
		if (-d $dir) {
			my $data = $pi->save();
			if (defined $data) {
				print "saving $plugin data to $dir/$plugin.storable\n";
				Storable::nstore $data, "$dir/$plugin.storable";
				print "compressing $dir/$plugin.storable\n";
				system '/usr/bin/gzip', '-f', "$dir/$plugin.storable";
			}
		}
	}
} #}}}
sub is_blocked { #{{{
	my $self = shift;
	my $who = lc shift;
	my $t = time;
	if (exists $self->{blocked}->{$who}) {
		if ($self->{blocked}->{$who} > 0) {
			if ($self->{blocked}->{$who} <= $t) {
				print STDERR "--- $who is blocked until $self->{blocked}->{$who}\n";
				return 1;
			}
			else {
				delete $self->{blocked}->{$who};
			}
		}
		else {
			print STDERR "--- $who is blocked indefinitely\n";
			return 1;
		}
	}
	return 0;
} #}}}
sub parsecommand { #{{{
	my $self = shift;
	my $mynick = shift;
	my $input = shift;

	return () unless $input->{command} eq 'PRIVMSG';
	my $re = '^(?:'.$mynick.'(?:[,:]\s*|\s+))?\.(\w+)\s*(.*)';
	if ($input->{params}->[1] =~ /$re/) {
		my $cmd = $1 // '';
		my $tail = $2 // '';
		my $addressee = $input->{name};
		if ($tail =~ /(.*?)\s*>\s*(\S+)$/) {
			$tail = $1;
			$addressee = $2;
			print STDERR "redirecting to $2\n";
		}
		my $rpltrg = $input->{params}->[0];
		$rpltrg = $input->{name} if $rpltrg eq $mynick;
		my @ret = ($rpltrg, $addressee, $cmd, $tail);
		return @ret;
	}
	return ();
} #}}}
sub distribute { #{{{
	my ($self, $mynick, $m) = @_;
	my @results = ();
	return () if $self->is_blocked($m->{name});
	my @c = $self->parsecommand($mynick, $m);
	if (@c and lc $c[2] eq 'plugin') {
		my $r = $self->interactive_commands($m, @c);
		push @results, $r if defined $r;
	}
	elsif (@c and lc $c[2] eq 'help' and $c[3] eq '') {
		push @results, ['PRIVMSG', $c[0], "$c[1]: .help plugin -- for help with plugins, .help NAME -- help on a specific named plugin (if available)"];
	}
	elsif (@c and $c[2] eq 'help' and lc $c[3] eq 'plugin') {
		return ['PRIVMSG', $c[0], "$c[1]: available commands: .plugin load|unload NAME, .plugin list available|loaded"];
	}
	else {
		for (keys %{$self->{plugins}}) {
			local $@ = '';
			my @plugres = ();
			eval {
				@plugres = $self->{plugins}->{$_}->handle_input($m, $mynick, @c);
			};
			if ($@ eq '') {
				push @results, @plugres;
			}
		}
	}
	return @results;
} #}}}
sub interactive_commands { #{{{
	my $self = shift;
	my $m = shift;
	my @c = @_;
	if ($c[3] =~ /(load|unload)\s+(\w+)/) {
		my $p = $2;
		if ($1 eq 'load') {
			my $ret = $self->try_load_plugin($p);
			if ($ret eq '') {
				return ['PRIVMSG', $c[0], "$c[1]: $p loaded"];
			}
			else {
				return ['PRIVMSG', $c[0], "$c[1]: $p failed to load ($ret)"];
			}
		}
		elsif ($1 eq 'unload') {
			my $ret = $self->try_unload_plugin($p);
			if ($ret eq '') {
				return ['PRIVMSG', $c[0], "$c[1]: $p unloaded"];
			}
			else {
				return ['PRIVMSG', $c[0], "$c[1]: $p failed to unload ($ret)"];
			}
		}
	}
	elsif ($c[3] =~ /list\s+(\w+)/) {
		if ($1 eq 'loaded') {
			return ['PRIVMSG', $c[0], "$c[1]: [".(join ' ', keys %{$self->{plugins}}).']'];
		}
		elsif ($1 eq 'available') {
			opendir my $dh, 'IRC_Bot/Plugins/';
			my @aps;
			while (my $pmf = readdir $dh) {
				if($pmf =~ /^([0-9A-Za-z_]+)\.pm$/) {
					push @aps, $1;
				}

			}
			closedir $dh;
			return ['PRIVMSG', $c[0], "$c[1]: [".(join ' ', @aps).']'];
		}
	}
	elsif ($c[3] =~ /block\s+(\w+)\s+(\d+)(\w)/) {
		my $t = time;
		my $who = $1;
		my $time = $2;
		my $unit = $3;
		$time *= 60 if $unit eq 'm';
		$time *= 60*60 if $unit eq 'h';
		$time *= 60*60*24 if $unit eq 'd';
		$time *= 60*60*24*7 if $unit eq 'w';
		$self->{block}->{lc $who} = $t + $time;
		print STDERR "--- blocking $who until $self->{blocked}->{$who}\n";
	}
	elsif ($c[3] =~ /block\s+(\w+)/) {
		my $who = $1;
		$self->{block}->{lc $who} = 0;
		print STDERR "--- blocking $who indefinitely\n";
	}
	elsif ($c[3] =~ /savestate/) {
		$self->save_plugin_state($_) for (keys %{$self->{plugins}});
	}
} #}}}
sub try_unload_all_plugins { #{{{
	my $self = shift;
	my $dir = $self->{persistence_dir};
	my @names = keys %{$self->{plugins}};
	for my $pn (@names) {
		$self->try_unload_plugin($pn, 1);
	}
	Storable::nstore $self->{blocked}, "$dir/PluginManager.storable";
	system '/usr/bin/gzip', '-f', "$dir/PluginManager.storable";
} #}}}
1;
