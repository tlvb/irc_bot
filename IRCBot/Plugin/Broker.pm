use warnings;
use strictures 2;
package IRCBot::Plugin::Broker;
use parent 'IRCBot::Plugin::PluginBase';
use IRCBot::DayLog;
use IRCBot::Event;
use Class::Unload;
use Try::Tiny;
use Storable;

sub new { #{{{
	my $class = shift;
	my $self = IRCBot::Plugin::PluginBase->new(
		@_,
		logcolor=>IRCBot::DayLog::blue()
	);

	@{$self}{qw/version plugin_instance/} = (
		'0.1.0-debug', {}
	);

	bless $self, $class;

	for my $p (@{$self->config->{plugin_list}}) {
		try {
			my ($m, $ok) = $self->load_plugin($p);
			$self->log_e("ERROR during broker init of plugin $p: $m") unless $ok;
		}
		catch {
			$self->log_e("exceptional FAILURE during broker init of plugin $p: $_");
		}
	}
	return $self;
} #}}}
sub get_plugin_names { #{{{
	my $self = shift;
	my $name = shift;
	$name =~ tr/[^a-zA-Z0-9_]//;
	my $tmp = $name =~ s/(?:^|_)(.)/\u$1/gr;
	my $package = "IRCBot::Plugin::$tmp";
	my $file = "IRCBot/Plugin/$tmp.pm";
	return ($name, $package, $file);
} #}}}
sub instantiate_plugin { #{{{
	# things in here do not have try catch/blocks, as they are supposed to be called
	# from parent functions with try catch/blocks.
	my $self = shift;
	my $name = shift;
	my $package = shift;
	my $file = shift;
	my $config = {};
	for (keys %{$self->config->{plugin_config}->{plugin_base}}) {
		$config->{$_} = $self->config->{plugin_config}->{plugin_base}->{$_};
	}
	if (exists $self->config->{plugin_config}->{$name}) {
		for (keys %{$self->config->{plugin_config}->{$name}}) {
			$config->{$_} = $self->config->{plugin_config}->{$name}->{$_};
		}
	}
	require $file;
	my $instance = $package->new(config=>$config, identity=>$self->identity);
	die "could not instantiate $name, new() returned undef" unless defined $instance;
	$self->{plugin_instance}->{$name} = $instance;
	my $version = $instance->version();
	if (-f "persistence/$name.storable") {
		my $condensate = Storable::retrieve "persisntence/$name.storable";
		$instance->evaporate($condensate) if defined $condensate;
	}
	$self->log_i("SUCCESS: instantiated plugin $package $version as $name from $file");
	return $version;
} #}}}
sub destroy_plugin { #{{{
	# things in here do not have try catch/blocks, as they are supposed to be called
	# from parent functions with try catch/blocks.
	my $self = shift;
	my $name = shift;
	my $package = shift;
	my $condensate = $self->{plugin_instance}->{$name}->condense();
	Storable::nstore $condensate, "persistence/$name.storable" if defined $condensate;
	my $version = $self->{plugin_instance}->{$name}->version();
	delete $self->{plugin_instance}->{$name};
	Class::Unload->unload($package);
	$self->log_i("SUCCESS: removed plugin $package $version as $name");
	return $version;
} #}}}
sub load_plugin { #{{{
	my $self = shift;
	my $plugin = shift;
	my $loadmode = shift // 'reload';
	my ($name, $package, $file) = $self->get_plugin_names($plugin);
	my $outversion = '[unknown]';
	my $inversion = '[unknown]';
	my @ret = ();
	if (exists $self->{plugin_instance}->{$name}) {
		if ($loadmode eq 'reload') {
			try {
				$outversion = $self->destroy_plugin($name, $package);
			}
			catch {
				@ret = ("error unloading $name $outversion: $_", undef);
			};
		}
		else {
			$outversion = $self->{plugin_instance}->{$name}->version;
			@ret = ("plugin $name $outversion already loaded", undef);
		}
		return @ret if @ret;
	}
	else {
		$outversion = undef;
	}
	if (-f $file) {
		try {
			$inversion = $self->instantiate_plugin($name, $package, $file);
		}
		catch {
			my $errmsg = $_;
			$errmsg =~ s/[\r\n]+/'+'/g;
			@ret = ("error loading $name $inversion: '$errmsg'", undef);
		};
	}
	else {
		@ret = ("The plugin '$name' is lacking the file containing its implementation.", undef);
	}
	return @ret if @ret;

	if ($outversion) {
		return ("reloaded $name $outversion -> $inversion", 1);
	}
	return ("loaded $name $inversion", 1);
} #}}}
sub unload_plugin { #{{{
	my $self = shift;
	my $plugin = shift;
	my ($name, $package, $file) = $self->get_plugin_names($plugin);
	my @ret = ();
	my $version = '[unknown]';
	if (exists $self->{plugin_instance}->{$name}) {
		if (exists $self->config->{plugin_config}->{$name}->{protected} and $self->config->{plugin_config}->{$name}->{protected}) {
			return $self->load_plugin($name, 'reload');
		}
		try {
			$version = $self->destroy_plugin($name, $package);
		}
		catch {
			@ret = ("error unloading $name $version: $_", undef);
		};
		return @ret if @ret;
		return ("unloaded $name $version", 1);
	}
	return ("not loaded: $name", 0);
} #}}}
sub process_events { #{{{
	my $self = shift;
	my %reload_list = ();
	my $ret = undef;

	while (1) {
		my @events = $self->get_events();
		last unless @events;
		for my $event (@events) {
			my $et = $event->type;
			if ($et eq 'GLOBAL-RESET') { #{{{
				# catch global reset events, since they have to be processed in the main loop
				$self->log_d("GLOBAL-RESET event caught.");
				$ret = 1;
			} #}}}
			elsif ($event->target eq 'broker' && $et =~ /PLUGIN-(?:UN|RE)?LOAD/) { #{{{
				# catch plugin handling events, since they are processed by the broker
				my ($res, $ok) = ();
				if ($et eq 'PLUGIN-LOAD') {
					($res, $ok) = $self->load_plugin($event->{plugin}, 'loadonly');
				}
				elsif ($et eq 'PLUGIN-UNLOAD') {
					($res, $ok) = $self->unload_plugin($event->{plugin});
				}
				elsif ($et eq 'PLUGIN-RELOAD') {
					($res, $ok) = $self->load_plugin($event->{plugin}, 'reload');
				}
				$self->emit_message(
					command=>'PRIVMSG',
					params=>[
						$event->{notify}->{respond},
						$event->{notify}->{address}.$res
					]
				);
			} #}}}
			else { #{{{
				if ( $event->target ne '*') { #{{{
					# unicast event
					if (exists $self->{plugin_instance}->{$event->target}) {
						try {
							$self->{plugin_instance}->{$event->target}->handle_event($event);
						}
						catch {
							$self->log_e("exceptional FAILURE when asking plugin ".$event->target." to handle event of type '".$event->type."': $_");
							$reload_list{$event->target} = 1;
						}
					}
				} #}}}
				else { #{{{
					# broadcast event
					for my $plugin (values %{$self->{plugin_instance}}) {
						try {
							$plugin->handle_event($event);
						}
						catch {
							$self->log_e("exceptional FAILURE when asking plugin $plugin to handle event of type '".$event->type."': $_");
							$reload_list{$event->target} = 1;
						};
					}
				} #}}}
			} #}}}
		}
	}
	if (exists $self->config->{reload_plugin_on_event_failure} && $self->config->{reload_plugin_on_event_failure}) {
		for my $plugin (keys %reload_list) {
			try {
				$self->load_plugin($plugin);
			}
			catch {
				$self->log_e("exceptional FAILURE when reloading plugin $plugin faliure to handle events: $_");
			}
		}
	}
	return $ret;
} #}}}
sub handle_message { #{{{
	my $self = shift;
	my $m = shift;
	my %ret = ();
	my %reload_list = ();
	for my $plugin (keys %{$self->{plugin_instance}}) {
		try {
			$self->{plugin_instance}->{$plugin}->handle_message($m);
		}
		catch {
			$self->log_e("exceptional FAILURE when asking plugin $plugin to handle input '".$m->deflate()."': $_");
			$reload_list{$plugin} = 1;
		};
	}
	if (exists $self->config->{reload_plugin_on_message_failure} && $self->config->{reload_plugin_on_message_failure}) {
		for my $plugin (keys %reload_list) {
			try {
				$self->load_plugin($plugin);
			}
			catch {
				$self->log_e("exceptional FAILURE when reloading plugin $plugin faliure to handle messages: $_");
			}
		}
	}
} #}}}
sub handle_timeout { #{{{
	my $self = shift;
	my %ret = ();
	for my $k (keys %{$self->{plugin_instance}}) {
		my $res = undef;
		try {
			$self->{plugin_instance}->{$k}->handle_timeout();
		}
		catch {
			$self->log_e("exceptional FAILURE when asking plugin $k to handle timeout event: $_");
		};
		if (defined $res) {
			if (exists $self->config->{plugin_config}->{$k}->{administrative} and $self->config->{plugin_config}->{$k}->{administrative}) {
				$ret{$k} = $res;
			}
		}
	}
	return %ret;
} #}}}
sub get_events { #{{{
	my $self = shift;
	my @ret = @{$self->{outgoing_events}};
	$self->{outgoing_events} = [];
	for my $k (keys %{$self->{plugin_instance}}) {
		try {
			push @ret, $self->{plugin_instance}->{$k}->get_events();
		}
		catch {
			$self->log_e("exceptional FAILURE when asking plugin $k for messages: $_");
		};
	}
	return @ret;
} #}}}
sub get_messages { #{{{
	my $self = shift;
	my @ret = @{$self->{outgoing_messages}};
	$self->{outgoing_messages} = [];
	for my $k (keys %{$self->{plugin_instance}}) {
		try {
			push @ret, $self->{plugin_instance}->{$k}->get_messages();
		}
		catch {
			$self->log_e("exceptional FAILURE when asking plugin $k for messages: $_");
		};
	}
	return @ret;
} #}}}
sub get_min_timeout { #{{{
	my $self = shift;
	my $timeout = -1;
	for my $k (keys %{$self->{plugin_instance}}) {
		my $t = -1;
		try {
			$t = $self->{plugin_instance}->{$k}->get_timeout();
		}
		catch {
			$self->log_e("exceptional FAILURE when asking plugin $k for timeout $_");
		};
		if (($t >= 0 and $timeout > $t) || $timeout <= 0) {
			$timeout = $t;
		}
	}
	return $timeout;
} #}}}
sub shutdown { #{{{
	my $self = shift;
	for my $k (keys %{$self->{plugin_instance}}) {
		try {
			$self->destroy_plugin($k, ref $self->{plugin_instance}->{$k});
		}
		catch {
			$self->log_e("FAILURE to destroy $k properly during shutdown: $_");
		};
	}
} #}}}
1;
