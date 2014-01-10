package xPL::Dock::ZiBase;

=head1 NAME

xPL::Dock::ZiBase - xPL::Dock plugin for Zodianet's ZiBase Home Automation
controller.

=head1 SYNOPSIS

 use xPL::Dock qw/ZiBase/;
 my $xpl = xPL::Dock->new(name => 'zibase');

 
 $XPL->main_loop();

=head1 DESCRIPTION

This module creates an xPL client for the ZiBase Home Automation controller.

=head1 METHODS

=cut

use Socket;
use xPL::ZiBase::ZiMessage;
use strict;
use warnings;

use English qw/-no_match_vars/;
use xPL::Dock::Plug;

our @ISA = qw(xPL::Dock::Plug);
our %EXPORT_TAGS = ( 'all' => [ qw() ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw();
our $VERSION = "0.23";

__PACKAGE__->make_readonly_accessor($_) foreach (qw/rfcom device/);


my $vendor_id = 'domoserv';


=head2 C<getopts( )>

This method returns the L<Getopt::Long> option definition for the
plugin.

=cut

sub getopts {
  my $self = shift;
  return
    (
     'zibase-verbose+' => \$self->{_verbose},
    );
}

=head2 C<init(%params)>

=cut

sub init {
  my $self = shift;
  my $xpl = shift;

  
  my %p = @_;

  # Ugly force vendor ID
  $xpl->{'_vendor_id'} = $vendor_id;

  
  $self->SUPER::init($xpl, @_);

  $self->{_zibase_ip} = "";
  $self->{_zibase_id} = "";
  $self->{_listen_port} = 0;

  # Create listening UDP socket
  my $listen;
  socket($listen, PF_INET, SOCK_DGRAM, getprotobyname('udp'));
  binmode $listen;

  # Setup the UDP listen socket
  my $ip = "0.0.0.0";
  my $port = 28734;   # Random value berk...
  my $okay = 0;

  while ($okay == 0) {
    if (bind($listen, sockaddr_in($port, inet_aton($ip)))) {
      $okay = 1;
      $self->{_listen_port} = $port;
    } else {
      warn "Could not bind socket to ".$ip.":".$port."... retrying...";
      sleep 1;
      $port += 1;
    }
    if ($port >= 65535) {
      die "Could not setup listening socket";
    }
  }

  # Listen socket opened and bound successfully
  print("Listening ZiBase messages on ".$ip.":".$port."\n") if $self->{_verbose};

  $self->{_listen_sock} = $listen;
  $xpl->add_input(handle => $listen, callback => sub { $self->zibase_message(@_) });


  # Send ZiBase discovery packet
  my $zmsg = new ZiMessage();
  $zmsg->{_command} = 8;

  my $sin = sockaddr_in(49999, inet_aton("255.255.255.255"));
  setsockopt $listen, SOL_SOCKET, SO_BROADCAST, 1;
  send($listen, $zmsg->getBinaryMessage(), 0, $sin);
  

  # Setup Rf commands hook callback

  $xpl->add_xpl_callback(id => 'xpl-rfcmd', callback => \&xpl_rfcmd,
                         arguments => $self,
                         filter =>
                         {
                          message_type => 'xpl-cmnd',
                          class => 'rfcmd',
                          class_type => 'basic',
                         }
						 );
  
    # Setup x10 commands hook callback
	$xpl->add_xpl_callback(id => 'xpl-x10cmd', callback => \&xpl_rfcmd,
                         arguments => $self,
                         filter =>
                         {
                          message_type => 'xpl-cmnd',
                          class => 'x10',
                          class_type => 'basic',
                         });
  
  # Setup scenario commands hook callback
  $xpl->add_xpl_callback(id => 'xpl-scencmd', callback => \&xpl_scencmd,
                         arguments => $self,
                         filter =>
                         {
                          message_type => 'xpl-cmnd',
                          class => 'scenario',
                          class_type => 'basic',
                         });

  # Setup script commands hook callback
  $xpl->add_xpl_callback(id => 'xpl-scriptcmd', callback => \&xpl_scriptcmd,
                         arguments => $self,
                         filter =>
                         {
                          message_type => 'xpl-cmnd',
                          class => 'script',
                          class_type => 'basic',
                         });
						 
  # Setup virtual probe event hook callback
  $xpl->add_xpl_callback(id => 'xpl-vpevnt', callback => \&xpl_vpevnt,
                         arguments => $self,
                         filter =>
                         {
                          message_type => 'xpl-cmnd',
                          class => 'vpevnt',
                          class_type => 'basic',
                         });

  return $self;
  
}

=head2 C<zibase_send_message(ZiMessage)>

Sends the specified ZiMessage over network to ZiBase.

=cut

sub zibase_send_message {
  my ($self, $zmsg) = @_;

  # Prepare sockaddr in structure
  my $sin = sockaddr_in(49999, inet_aton($self->{_zibase_ip}));
  # Force socket options
  setsockopt $self->{_listen_sock}, SOL_SOCKET, SO_BROADCAST, 1;
  # Send ZiMessage payload
  send($self->{_listen_sock}, $zmsg->getBinaryMessage(), 0, $sin);
}

=head2 C<zibase_register_host()>

Register the host with the ZiBase to start receive messages.

=cut

sub zibase_register_host {
  my ($self) = @_;

  # Construct zibase message and send it
  my $zmsg = new ZiMessage();
  $zmsg->setRegisterHost($self->{_xpl}->{_ip}, $self->{_listen_port});
  $self->zibase_send_message($zmsg);
}

=head2 C<xpl_rfcmd(%xpl_callback_parameters)>

This is the callback that processes incoming xPL messages.  It handles
the incoming rfcmd.basic schema messages.

=cut

sub xpl_rfcmd {
  my %p = @_;
  my $msg = $p{message};
  my $peeraddr = $p{peeraddr};
  my $peerport = $p{peerport};
  my $self = $p{arguments};

  my $repeatcnt = $msg->field('repeat')||0;

  my $m_device = $msg->field('device');
  my $m_command = $msg->field('command');
  my $m_protocol = $msg->field('protocol')||'preset';    
  my $m_level = $msg->field('level');
  
  # Send corresponding command to zibase
  $self->zibase_command($m_device, $m_command, $m_protocol, $m_level, $repeatcnt);

  return 1;
}

=head2 C<xpl_scencmd(%xpl_callback_parameters)>

This is the callback that processes incoming xPL messages.  It handles
the incoming scencmd.basic schema messages.

=cut

sub xpl_scencmd {
  my %p = @_;
  my $msg = $p{message};
  my $peeraddr = $p{peeraddr};
  my $peerport = $p{peerport};
  my $self = $p{arguments};

  my $m_scenario = $msg->field('scenario');

  # Send corresponding command to zibase
  $self->zibase_execScenario($m_scenario);

  return 1;
}

=head2 C<xpl_scriptcmd(%xpl_callback_parameters)>

This is the callback that processes incoming xPL messages.  It handles
the incoming scriptcmd.basic schema messages.

=cut

sub xpl_scriptcmd {
  my %p = @_;
  my $msg = $p{message};
  my $peeraddr = $p{peeraddr};
  my $peerport = $p{peerport};
  my $self = $p{arguments};

  my $m_script = $msg->field('script');

  # Send corresponding command to zibase
  $self->zibase_execScript($m_script);

  return 1;
}

=head2 C<xpl_vpevnt(%xpl_callback_parameters)>

This is the callback that processes incoming xPL messages.  It handles
the incoming vpevnt.basic schema messages.

=cut

sub xpl_vpevnt {
  my %p = @_;
  my $msg = $p{message};
  my $peeraddr = $p{peeraddr};
  my $peerport = $p{peerport};
  my $self = $p{arguments};

  my $m_id = $msg->field('id');

  my $m_type = $msg->field('type');
  my $m_c1 = $msg->field('c1');
  my $m_c2 = $msg->field('c2');
  my $m_batt = $msg->field('batt');
 
  # Send corresponding command to zibase
  $self->zibase_vpevnt($m_id, $m_type, $m_c1, $m_c2, $m_batt);

  return 1;
}

=head2 C<zibase_command($device, $command, $protocol, $dimlevel, $nbrepeat, $peeraddr)>

Sends the specified RF command to ZiBase

=cut

sub zibase_command {
  my ($self, $device, $command, $protocol, $level, $nbrepeat) = @_;

  my $zmsg = new ZiMessage();
  # Set ZiMessage parameters
  $protocol=lc($protocol);
  $command=lc($command);
  $zmsg->setRFCommand($command, $protocol, $level, $nbrepeat, $self->{_zibase_ip}, $device);
  $zmsg->setRFAddress($device);
  # Send it over network
  if (($command eq 'dim' || $command eq 'bright') && $protocol eq 'zwave'){
  } else {
    $self->zibase_send_message($zmsg);
  }
  # Send corresponding xPL Trigger
  if ($protocol eq 'x10'|| $protocol eq 'preset') {
     $self->xpl_send_x10($device, $command, $protocol, $level);
  } else {
     $self->xpl_send_rfcmd($device, $command, $protocol, $level);
  }
}

=head2 C<zibase_execScenario($scenario)>

Sends the request to ZiBase to execute a scenario

=cut

sub zibase_execScenario {
  my ($self, $scenario) = @_;

  my $zmsg = new ZiMessage();
  # Set ZiMessage parameters
  $zmsg->setRFexecScenario($scenario);
  # Send it over network
  $self->zibase_send_message($zmsg);
  # Send corresponding xPL Trigger
  $self->xpl_send_scenario($scenario);
}

=head2 C<zibase_execScript($script)>

Sends the request to ZiBase to execute a script

=cut

sub zibase_execScript {
  my ($self, $script) = @_;

  my $zmsg = new ZiMessage();
  # Set ZiMessage parameters
  $zmsg->setRFexecScript($script);
  # Send it over network
  $self->zibase_send_message($zmsg);
  # Send corresponding xPL Trigger
  $self->xpl_send_script($script);
}

=head2 C<zibase_vpevnt($id, $type, $c1, $c2, $batt)>

Sends the specified virtual probe event to ZiBase

=cut

sub zibase_vpevnt {
  my ($self, $id, $type, $c1, $c2, $batt) = @_;

  my $zmsg = new ZiMessage();
  # Set ZiMessage parameters
  $zmsg->setVPEvent($id, $type, $c1, $c2, $batt);
  # Send it over network
  $self->zibase_send_message($zmsg);
  # Send corresponding xPL Trigger
  # $self->xpl_send_vpevnt($id, $type, $c1, $c2, $batt);
}


=head2 C<zibase_message($file_handle)>

This method is called when the agent receives a ZiBase message.

=cut

sub zibase_message {
  my $self = shift;
  my $sock = $self->{_listen_sock};
  my $buf = '';
  my $addr = recv($sock, $buf, 1500, 0);
  my ($peerport, $peeraddr) = sockaddr_in($addr);
  $peeraddr = inet_ntoa($peeraddr);

  # Create message and initialize it from received payload
  my $zmsg = new ZiMessage();
  $zmsg->fromPayload($buf);


  if ($zmsg->is_ack()) {
    # This is an ACK
    if ($self->{_zibase_ip} eq "") {
      # If first received ACK, register ZiBase IP:PORT
      $self->{_zibase_ip} = $peeraddr;
      $self->{_zibase_id} = $zmsg->{_zibase_id};
      print "Found ZiBase '".$zmsg->{_zibase_id}."' at IP ".$peeraddr."\n" if $self->{_verbose};
      $self->zibase_register_host();
    }
  } elsif ($zmsg->is_rfreceive()) {
    # Print received RF ZiMessage
    print("Received : ".$zmsg->{_message}."\n") if $self->{_verbose};
    $self->zibase_rfreceive_decode($zmsg->{_message});
  } else {
    warn "Received an unknown Message from ZiBase ".$zmsg->{_command}." !!!";
  }  

  return (1);
}

=head2 C<xpl_send_sensor($devid, $unit, $value)>

This method sends a sensor.basic trigger message over the xPL network.
  devid = device identifier
  unit = device type (eg. temp, humidity, ...)
  value = sensor value

=cut

sub xpl_send_sensor {
  my ($self, $devid, $unit, $value) = @_;

  my $xplmsg =
     xPL::Message->new(message_type => 'xpl-trig',
                       head => { source => $self->xpl->id, },
                       schema => 'sensor.basic',
                       body =>
                       [ 
                        device => $devid,
                        type => $unit,
                        current => $value,
                       ]);
  print $xplmsg->summary,"\n" if $self->{_verbose};
  $self->xpl->send($xplmsg);
}

=head2 C<xpl_send_x10($device, $command, $protocol, $level)>

This method sends a x10.basic trigger message over the xPL network.
 device = device identifier (eg. B2, P12...)
  command = x10 command (on, off)
  protocol = protocol rf (zwave, x10 ...)
  level = dim level (0 to 100)

=cut

sub xpl_send_x10 {
  my ($self, $device, $command, $protocol, $level) = @_;
  my $xplmsg;

  if ($command eq 'dim' || $command eq 'bright') {
    $xplmsg =
     xPL::Message->new(message_type => 'xpl-trig',
                       head => { source => $self->xpl->id, },
                       schema => 'x10.basic',
                       body =>
                       [
                        device => lc($device),
                        command => lc($command),
                        protocol => lc($protocol),
			level => $level,
                       ]);
  } else {
    $xplmsg =
     xPL::Message->new(message_type => 'xpl-trig',
                       head => { source => $self->xpl->id, },
                       schema => 'x10.basic',
                       body =>
                       [
                        device => lc($device),
                        command => lc($command),
                        protocol => lc($protocol),
                       ]);
  }
  print $xplmsg->summary,"\n" if $self->{_verbose};
  $self->xpl->send($xplmsg);
}

=head2 C<xpl_send_rfcmd($device, $command, $protocol, $level)>

This method sends a rfcmd.basic trigger message over the xPL network.
  device = device identifier (eg. B2, P12...)
  command = x10 command (on, off)
  protocol = protocol rf (zwave, x10 ...)
  level = dim level (0 to 100)

=cut


sub xpl_send_rfcmd {
  my ($self, $device, $command, $protocol, $level) = @_;
  my $xplmsg;

  if ($command eq 'dim' || $command eq 'bright') {
    $xplmsg =
     xPL::Message->new(message_type => 'xpl-trig',
                       head => { source => $self->xpl->id, },
                       schema => 'rfcmd.basic',
                       body =>
                       [
						device => lc($device),
						command => lc($command),
						protocol => lc($protocol),
						level => $level,
                       ]);
  } else {
    $xplmsg =
     xPL::Message->new(message_type => 'xpl-trig',
                       head => { source => $self->xpl->id, },
                       schema => 'rfcmd.basic',
                       body =>
                       [
                        device => lc($device),
                        command => lc($command),
                        protocol => lc($protocol),
                       ]);
  }
  print $xplmsg->summary,"\n" if $self->{_verbose};
  $self->xpl->send($xplmsg);
}

=head2 C<xpl_send_scenario($scenario)>

This method sends a scenario.basic trigger message over the xPL network.
  scenario = number of the scenario to execute

=cut

sub xpl_send_scenario {
  my ($self, $scenario) = @_;
  my $xplmsg;
 $xplmsg =
     xPL::Message->new(message_type => 'xpl-trig',
                       head => { source => $self->xpl->id, },
                       schema => 'scenario.basic',
                       body =>
                       [
                        scenario => lc($scenario),
                        command => "execute",
                       ]);
  print $xplmsg->summary,"\n" if $self->{_verbose};
  $self->xpl->send($xplmsg);
}

=head2 C<xpl_send_script($script)>

This method sends a script.basic trigger message over the xPL network.
  script = the command script that zibase have to execute
  exemple "lm [toto]" launch scenario label as toto 
          "lm 2 aft 3600" launch scenario 2 after 3600 seconds
          "lm [toto].lm [tata]" launch scenario label as toto and after launch scenario label as tata
		  
=cut

sub xpl_send_script {
  my ($self, $script) = @_;
  my $xplmsg;
 $xplmsg =
     xPL::Message->new(message_type => 'xpl-trig',
                       head => { source => $self->xpl->id, },
                       schema => 'script.basic',
                       body =>
                       [
                        script => $script,
                        command => "execute",
                       ]);
  print $xplmsg->summary,"\n" if $self->{_verbose};
  $self->xpl->send($xplmsg);
}

# =head2 C<xpl_send_vpevnt($id, $type, $c1, $c2, $batt)>

# This method sends a vpevnt.basic trigger message over the xPL network.

# =cut

# sub xpl_send_vpevnt {
 # my ($self, $id, $type, $c1, $c2, $batt) = @_;
 # my $xplmsg;
 # $xplmsg =
     # xPL::Message->new(message_type => 'xpl-trig',
                       # head => { source => $self->xpl->id, },
                       # schema => 'vpevnt.basic',
                       # body =>
                       # [
                        # id => $id,
						# type => lc($type),
                        # command => "vpevent",
						# c1 => $c1,
						# c2 => $c2,
						# batt => $batt,
                       # ]);
  # print $xplmsg->summary,"\n" if $self->{_verbose};
  # $self->xpl->send($xplmsg);
# }


sub zibase_rfreceive_decode {
  my ($self, $msg) = @_;

  if ($msg =~ /^Received radio ID\ /) {
    # This actually is a RF radio message
    my $devid = "";
    if ($msg =~ /\<id\>(\w+)\<\/id\>/) {
      $devid = $1;
    }
    # Try to guess device type for Oregon Scientific sensors
    if ($msg =~ /THN132N/) {
      $devid = "thn132n.".$devid;
    } elsif ($msg =~ /THGR228N/) {
      $devid = "thgr228n.".$devid;
    } elsif ($msg =~ /PCR800/) {
      $devid = "pcr800.".$devid;
    }

	

    # Test status value (for Home Automation remotes)
	if ($msg =~ /\<sta\>\+?(.*)\<\/sta\>/) {
      my $sta = $1;
      $self->xpl_send_sensor($devid, 'input', ($sta eq "ON") ? "high" : "low");
    }
    # Test temperature value
    if ($msg =~ /\<tem\>\+?(.*)\<\/tem\>/) {
      $self->xpl_send_sensor($devid, 'temp', $1);
    }
    # Test current rain
    if ($msg =~ /\<cra\>(.*)\<\/cra\>/) {
      $self->xpl_send_sensor($devid, 'current_rain', $1);
    }
    # Test Total Rain
    if ($msg =~ /\<tra\>(.*)\<\/tra\>/) {
      $self->xpl_send_sensor($devid, 'total_rain', $1);
    }
    # Test Humidity
    if ($msg =~ /\<hum\>(.*)\<\/hum\>/) {
      $self->xpl_send_sensor($devid, 'humidity', $1);
    }
    # Test UV
    if ($msg =~ /\<uvl\>(.*)\<\/uvl\>/) {
      $self->xpl_send_sensor($devid, 'uv', $1);
    }
    # Test Power (in kw)
    if ($msg =~ /\<kw\>(.*)\<\/kw\>/) {
      $self->xpl_send_sensor($devid, 'power', $1);
    }
    # Test energy consumption
    if ($msg =~ /\<kwh\>(.*)\<\/kwh\>/) {
      $self->xpl_send_sensor($devid, 'energy', $1);
    }
    # Test Wind speed (m/s)
    if ($msg =~ /\<awi\>(.*)\<\/awi\>/) {
      $self->xpl_send_sensor($devid, 'speed', $1);
    }
    # Test Wind direction
    if ($msg =~ /\<dir\>(.*)\<\/dir\>/) {
      $self->xpl_send_sensor($devid, 'direction', $1);
    }
	# Test Battery
	if ($msg =~ /Batt=\<bat\>Ok\<\/bat\>/) {
	  $self-> xpl_send_sensor($devid, 'battery', 'Ok')
	}
	if ($msg =~ /Batt=\<bat\>Low\<\/bat\>/) {
	  $self-> xpl_send_sensor($devid, 'battery', 'Low')
	}
	if ($msg =~ /\<dev\>\+?(.*)\<\/dev\>/) {
      my $dev = $1;
	  if ($dev eq "CMD") {
		$self->xpl_send_sensor($devid, 'cmd', 'On');
	  } elsif ($dev eq "Visonic") {
	    if ($msg =~ /Flags= \<flag1\>Alarm\<\/flag1\>/) {
		  $self->xpl_send_sensor($devid, 'alarm', 'On');
		}
	  }
    }
    if ($devid =~ /^(Z[A-P]\d\d?)_ON$/) {
      $self->xpl_send_rfcmd($1, 'on', 'zwave', 100);
    }
    if ($devid =~ /^(Z[A-P]\d\d?)_OFF$/) {
      $self->xpl_send_rfcmd($1, 'off', 'zwave', 0);
    }
    if ($devid =~ /^(Z[A-P]\d\d?)$/) {
      $self->xpl_send_rfcmd($1, 'on', 'zwave', 100);
    }
    # Finally test if this is a pure X10 message
    if ($devid =~ /^([A-P]\d\d?)$/) {
      $self->xpl_send_x10($1, 'on', 'x10', 100);
    }
    if ($devid =~ /^([A-P]\d\d?)_OFF$/) {
      $self->xpl_send_x10($1, 'off', 'x10', 0);
    }
  } 
  # elsif  ($msg =~ /^Sent radio ID\ /) {
    
	# Test if this is pure ZWAVE message
	# if ($devid =~ /^(Z[A-P]\d\d?)_ON$/) {
      # $self->xpl_send_rfcmd($1, 'on', 'zwave', 100);
    # }
    # if ($devid =~ /^(Z[A-P]\d\d?)_OFF$/) {
      # $self->xpl_send_rfcmd($1, 'off', 'zwave', 0);
    # }
	# if ($devid =~ /^([A-P]\d\d?)_DIM/SPECIAL$/) {
      # $self->xpl_send_rfcmd($1, 'dim', 'zwave');
    # }
	# if ($devid =~ /^(Z[A-P]\d\d?)_DIM/SPECIAL$/) {
      # $self->xpl_send_rfcmd($1, 'dim', 'zwave');
    # }
    # Finally test if this is a pure X10 message
    # if ($devid =~ /^([A-P]\d\d?)$/) {
      # $self->xpl_send_x10($1, 'on', 'x10', 100);
    # }
    # if ($devid =~ /^([A-P]\d\d?)_OFF$/) {
      # $self->xpl_send_x10($1, 'off', 'x10', 0);
    # }
	# if ($devid =~ /^([A-P]\d\d?)_DIM/SPECIAL$/) {
      # $self->xpl_send_x10($1, 'dim', 'x10');
    # }
}

1;
__END__

=head1 API VERSION

This module has been developed for ZiBases supporting the ZAPI v1.6
ZiBase firmware should be >= 559

=head1 EXPORT

None by default.

=head1 SEE ALSO

xpl-zibase(1)

Authors website: http://www.poulpy.com
				Modified by hellorheaven

xPL Perl website: http://www.xpl-perl.org.uk/

Zodianet website: http://www.zodianet.com

=head1 AUTHOR

ZiBase module:
Thibault Lamy, E<lt>titi@poulpy.comE<gt>
Mickael Zerbib(alias hellorheaven), E<lt>mickradio@hotmail.comE<gt>

xpl-perl:
Mark Hindess, E<lt>soft-xpl-perl@temporalanomaly.comE<gt>

=head1 COPYRIGHT

Copyright (C) 2011 by Thibault Lamy

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.7 or,
at your option, any later version of Perl 5 you may have available.

=cut
