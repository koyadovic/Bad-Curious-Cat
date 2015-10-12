#!C:\strawberry\perl\bin\perl.exe
#
# NetCheck.pl
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

use utf8;
use Switch;
use Encode qw(decode encode);
use POSIX 'strftime';

use DBI;
use DBI qw(:sql_types);

use List::Util 'shuffle';
use List::MoreUtils qw(uniq);

use Win32::GUI();

#########################################################
# Para tocar
my $rutadb				= "database.db";

# For the console
my $columns				= 140;
my $lines_max				= 55;
my $lines_min				= 4;
my $console_encoding			= "cp850";

# For the window
my $window_encoding			= "iso-8859-15";

# Timing options of the scan function.
# Each scan call check one record in networks table.
my $seconds_to_wait_for_each_scan_call	= 10;
my $max_scan_children_processes		= 10;
my $max_simultaneous_scans		= 3;


#########################################################
# Global variables (NO TOCAR)
my $tool_name				= "Bad Curious Cat";
my @users_to_ignore;
my @active_hours			= (10, 13, 17);
my $last_active_hour			= -1;
my $h, $last_h;

my $debug_get_serial_number		= 0;
my $debug_get_computer_name		= 0;
my $debug_get_model			= 0;
my $debug_get_operating_system		= 0;
my $debug_get_db_user			= 0;
my $debug_get_ad_complete_name		= 0;
my $debug_add_db_user			= 0;
my $debug_get_computer_users		= 0;
my $debug_associate_user_to_computer	= 0;
my $debug_get_alive_ips			= 0;
my $debug_scan				= 0;
my $debug_main				= 0;

my $actived;

$SIG{CHLD} = 'IGNORE'; 			# To avoid zombie processes.

#########################################################
# Win32 main Window
my $width = 800;
my $height = 250;

# Icono
#my $icon = Win32::GUI::Icon->new("cci.ico");

# Creamos la ventana
my $main = Win32::GUI::Window->new(
	-name		=>	'Main',
	-width		=>	$width,
	-height		=>	$height,
	-title		=>	'Curious Cat Indexer',
	-minsize	=>	[$width, $height],
	-maxsize	=>	[$width, $height],
);
#$main->SetIcon($icon);

# Imagen
# my $cci = Win32::GUI::Bitmap->new("cci.bmp");

sub Main_Terminate {
	-1;
}


# Escondemos la ventana del terminal
my $hw = Win32::GUI::GetPerlWindow();
Win32::GUI::Hide($hw);

# Centramos la ventana
my $desk = Win32::GUI::GetDesktopWindow();
my $wi = Win32::GUI::Width($desk);
my $he = Win32::GUI::Height($desk);
my $x = ($wi - $width) / 2;
my $y = ($he - $height) / 2;
$main->Move($x, $y);


# Textfield dpnde iremos volcando la información.
my $textf = $main->AddTextfield(
	-name		=>	"TextField",
	-left		=>	0,
	-top		=>	1,
	-width		=>	$width - 10,
	-height		=>	$height - 26,
	-background	=>	[50,	50,	50],
	-foreground	=>	[0,	250,	200],
	-multiline	=>	1,
	-readonly	=>	1,
	-vscroll	=>	1,
);


#########################################################

sub get_database {
	my $db = DBI->connect("dbi:SQLite:" . $rutadb, "", "", {RaiseError => 1, AutoCommit => 1});
	$db->{sqlite_unicode} = 1;
	$db->sqlite_busy_timeout(1800000);

	return $db;
}

sub sql_do {
	my ($query)		= @_;

	my $error		= 1;
	while($error) {
		my $db		= get_database();

		$db->do($query);
		sleep 5 if $db->err;
		$error		= $db->err;

		$db->disconnect;
	}
}

sub sql_selectall_arrayref {
	my ($query)			= @_;

	my $all;	

	my $error			= 1;
	while($error) {
		my $db_read		= get_database();
		$all			= $db_read->selectall_arrayref($query);

		sleep 5 if $db_read->err;
		$error			= $db_read->err;

		$db_read->disconnect;
	}

	return $all;
}

sub get_current_hour {
	($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();
	return $hour;
}

sub get_timestamp {
	my $timestamp	= strftime("%H:%M", localtime);

	return $timestamp;
}

sub get_current_datetime {
	my $datetime	= strftime("%Y-%m-%d %H:%M:%S", localtime);

	return $datetime;
}

# Ya que usamos UTF-8, codifica los prints para que en la consola de Windows se vea todo correctamente
sub p {
	my ($original_text)	= @_;
	my $t			= get_timestamp();
	my $pid			= $$;
	$pid			= sprintf '%6s', $pid;

	# A la terminal
	$text			= encode($console_encoding, $original_text);
	print " [$t] [$pid] $text";

	# A la ventana de Windows.
	chomp($original_text);
	$original_text		= encode($window_encoding, $original_text);
	$textf->Append("\r\n") if($textf->Text() ne "");
	$textf->Append("[$t] [$pid] $original_text");
	Win32::GUI::DoEvents();
}

sub get_serial_number {
	my ($objetivo)	= @_;
	my $numeroserie	= "";


	for (my $i = 0; $i < 2; $i ++) {
		if(!$numeroserie) {
			$numeroserie	= `wmic /node:$objetivo bios get serialnumber /format:list 2>NUL`;
			$numeroserie	=~ s/SerialNumber=//;
			$numeroserie	=~ s/[\r\n]//g;

			sleep 1 if(!$numeroserie);
		}
	}

	p("get_serial_number:\t\tObjetivo: $objetivo, S\/N: $numeroserie\n") if ($debug_get_serial_number);

	return $numeroserie;
}

sub get_computer_name {
	my $equipo	= "";
	my ($objetivo)	= @_;

	# primer método
	$equipo		= `wmic /node:$objetivo computersystem get name /format:list 2>NUL`;
	$equipo		=~s/[\r,\n,Name=]//g;
	chomp($equipo);

	# método alternativo
	if(!$equipo) {
		sleep 1;
		my @lineas	= `nbtstat -a $objetivo`;
		@lineas		= grep { $_ =~ /\<20\>/; } @lineas;
		($equipo)	= @lineas;
		$equipo		=~ s/\s+([\S]+)\s+<20>.*/\1/;
		chomp($equipo);
	}

	#método alternativo 2
	if(!$equipo) {
		sleep 1;
		my @lineas	= `ping -a -n 1 $objetivo`;
		@lineas		= grep { $_ =~ /\[$objetivo\]/; } @lineas;
		($equipo)	= @lineas;
		$equipo		=~ s/.*\s([\S]+)\s\[$objetivo\].*/\1/;
		chomp($equipo);
	}

	p("get_computer_name:\t\tObjetivo: $objetivo, Equipo: $equipo.\n") if ($debug_get_computer_name);

	return $equipo;
}

sub get_model {
	my ($objetivo) = @_;

	my $modelo	= `wmic /node:$objetivo computersystem get model /format:list 2>NUL`;
	$modelo		=~ s/Model=//;
	$modelo		=~ s/[\r\n]//g;

	chomp($modelo);

	p("get_model:\t\t\tObjetivo: $objetivo, Modelo: $modelo.\n") if($debug_get_model);

	return $modelo;
}

sub get_operating_system {
	my ($objetivo) = @_;

	my $sistemaoperativo	= `wmic /node:$objetivo os get name /format:list 2>NUL`;
	$sistemaoperativo	=~ s/Name=//;
	$sistemaoperativo	=~ s/[\r\n]//g;
	$sistemaoperativo	=~ s/\|.*//;
	$sistemaoperativo	=~ s/\s+$//;

	chomp($sistemaoperativo);

	p("get_operating_system:\t\tObjetivo: $objetivo, Sistema operativo: $sistemaoperativo.\n") if($debug_get_operating_system);

	return $sistemaoperativo;
}

sub get_db_user {
	my %result		= ();

	my ($user_to_query)	= @_;
	uc($user_to_query);


	my $sql			= "SELECT * FROM users WHERE username = \'$user_to_query\'";
	my $all			= sql_selectall_arrayref($sql);

	my $db_user_name, $db_complete_name, $t = 0;

	foreach my $row (@$all) {
		$t 		= 1;
		($db_user_name, $db_complete_name) = @$row;
	}

	if($t){
		p("get_db_user:\t\t\t$user_to_query existe en la db local.\n") if($debug_get_db_user);
		$result{$user_to_query} = $db_complete_name;
	} else {
		p("get_db_user:\t\t\t$user_to_query no existe en la db local. Tendrá que ser consultado AD.\n") if($debug_get_db_user);
	}

	return %result;
}

sub get_ad_complete_name {
	my ($user_to_query) = @_;
	uc($user_to_query);

	$user_to_query =~ s/\s+//g;

	if($user_to_query) {

		for (my $i = 0; $i < 2; $i++){
			my @result = `dsquery user -samid $user_to_query\|dsget user -samid -fn -ln 2>NUL`;

			foreach(@result) {
				if($_ =~ /$user_to_query/i) {

					my $line	= $_;
					$line		=~ s/\s+/ /g;
					$line		=~ s/(^\s*|\s*$)//g;
					$line		=~ s/[\d\w]+\s(.+)/\1/;

					$line = decode('cp850', $line);

					p("get_ad_complete_name:\t\t$user_to_query ->\t$line\n") if ($debug_get_ad_complete_name);
					return $line;
				}
			}
			sleep 1;
		}
	}
	p("get_ad_complete_name:\t\t$user_to_query ->\tSin resultados\n") if ($debug_get_ad_complete_name);
	return "";
}

# username, complete name (the two parameters needed)
sub add_db_user {
	my ($username, $complete_name) = @_;
	sql_do("INSERT INTO users VALUES (\'$username\', \'$complete_name\')");
	p("add_db_user:\t\t\t$username ->\t$complete_name\n") if ($debug_add_db_user);
}

sub get_computer_users {
	my ($computer) = @_;

	my @users=();

	my $ruta;
	my @rutas = (	"\\\\$computer\\d\$\\Users",
			"\\\\$computer\\c\$\\Users",
			"\\\\$computer\\d\$\\Documents and Settings\\",
			"\\\\$computer\\c\$\\Documents and Settings\\");

	my $max_users = 0;
	my $max_ruta = "";
	my @users_temp=();

	foreach (@rutas){
		chomp;
		if(-d "$_"){
			$ruta		= $_;
			my $tmp		= `dir /AD /B \"$ruta\" 2>NUL`;
			@users_temp	= split('\n', $tmp);

			if($#users_temp + 1 > $max_users) {

				$max_users	= $#users_temp + 1;
				$max_ruta	= $ruta;
				@users		= @users_temp;
			}
		}
	}

	foreach(@users){
		chomp;
		$_ = uc;
		$_ =~ s/^\s*([\w\d ]+)\.?.*$/\1/;
		
	}

	if (($#users_to_ignore + 1) > 0) {
		my $ignore_users	= "(";
		$ignore_users 		.= join('|', @users_to_ignore);
		$ignore_users		.= ")";

		@users = grep { $_ !~ /$ignore_users/i; } @users;
	}

	@users = grep { $_ ne ""; } @users;
	@users = uniq @users;

	p("get_computer_users:\t\tEncontrado en $max_ruta: @users\n") if ($debug_get_computer_users);

	return @users;
}


# serial, computer name, user, user complete name (four parameters needed)
sub associate_user_to_computer {
	my ($serialnumber, $computer_name, $user, $complete_name) = @_;
	my $all;

	if($serialnumber && $computer_name && $user) {

		$all = sql_selectall_arrayref("SELECT * FROM computers_and_users WHERE serial = \'$serialnumber\' AND computer_name=\'$computer_name\' AND username=\'$user\'");

		my $db_serial, $db_user_name, $t = 0;

		foreach my $row (@$all) {

			$t = 1;

			($db_serial, $db_computer_name, $db_user_name, $db_complete_name) = @$row;

		}

		if(!$t){
			sql_do("INSERT INTO computers_and_users VALUES (\'$serialnumber\', \'$computer_name\', \'$user\', \'$complete_name\')");
			p("associate_user_to_computer:\t$user ->\t$serialnumber\t$computer_name\n") if ($debug_associate_user_to_computer);
		}
	}

}

sub get_users_to_ignore {
	my $all = sql_selectall_arrayref("SELECT username FROM users_to_ignore");
	my @users = ();

	my $username;
	foreach my $row (@$all) {
		($username) = @$row;
		uc($username);
		push(@users, $username);
	}

	return @users;
}

sub get_all_networks {
	my $all = sql_selectall_arrayref("SELECT network FROM networks");
	my @networks = ();

	my $network;
	foreach my $row (@$all) {
		($network) = @$row;
		push(@networks, $network);
	}

	return @networks;
}

sub get_alive_ips {
	my ($network) = @_;
	my @resultados = `nmap -sP -n $network 2>NUL`;

	@resultados = grep { $_ =~ /\d+\.\d+\.\d+\.\d+/; } @resultados;

	foreach (@resultados) {
		chomp();
		$_ =~ s/.* (\d+\.\d+\.\d+\.\d+).*/\1/;
		$_ =~ s/(^\s+|\s+$)//g;
	}

	@resultados = shuffle(@resultados);

	p("get_alive_ips:\t\t" . ($#resultados + 1) . " IPs activas en la red $network\n") if($debug_get_alive_ips);

	return @resultados;
}

sub scan {
	# Cogemos el parámetro en el que se especificará la red que husmear.
	my $network 			= shift;
	chomp($network);

	# De la red, nos quedamos con las direcciones IP que responden a ping.
	my @resultados 			= get_alive_ips($network);

	p("scan:\t\t\t\tEscaneando " . ($#resultados + 1) . " IPs en $network.\n") if($debug_scan);

	my $hijos			= 0;
	foreach $objetivo (@resultados){

		# Si los procesos hijo han superado el límite esperamos.
		if ($hijos >= $max_scan_children_processes) {
			$pid=wait();
			$hijos--;
		}

		# Hacemos un nuevo proceso hijo
		$pid = fork();

		# Si el $pid es 0, es que se trata del proceso hijo
		if(!$pid){
			# SERIAL NUMBER
			my $numeroserie = get_serial_number($objetivo);

			if($numeroserie) {
				my $equipo = "", $modelo = "", $sistemaoperativo = "";

				# Hacemos dos intentos			
				for (my $i = 0; $i < 2; $i++){
					# NOMBRE DE EQUIPO
					$equipo			= get_computer_name($objetivo) if (!$equipo);

					# MODELO
					$modelo			= get_model($objetivo) if (!$modelo);

					# OS
					$sistemaoperativo	= get_operating_system($objetivo) if (!$sistemaoperativo);
				}

				if ($equipo){
					$time = get_current_datetime();

					my $all = sql_selectall_arrayref("SELECT * FROM computers WHERE serial=\'$numeroserie\' " .
									"AND name=\'$equipo\'");
				
					my $t = 0;
					my $db_serial, $db_name, $db_model, $db_os, $db_last_ip, $db_first_seen, $db_last_seen;
					foreach my $row (@$all) {
						$t = 1;
						($db_serial, $db_name, $db_model, $db_os, $db_last_ip, $db_first_seen, $db_last_seen) = @$row;
					}

					if(!$t){
						# No existe en la DB, hay que añadirlo.
						sql_do(	"INSERT INTO computers VALUES (\'$numeroserie\', \'$equipo\', " .
							"\'$modelo\', \'$sistemaoperativo\', \'$objetivo\', \'$time\', \'$time\')");

						p("scan:\t\t\t\tAñadimos:\t\t\t$numeroserie\t$equipo\t$objetivo\n") if($debug_scan);					

					} else {
						# Sí que existe en la DB, hay que actualizarlo.
						my $query = "";

						$query .= "UPDATE computers SET ";
						$query .= "model=\'$modelo\', " if ($modelo && !$db_model);
						$query .= "os=\'$sistemaoperativo\', " if ($sistemaoperativo && !$db_os);
						$query .= "last_ip=\'$objetivo\', ";
						$query .= "last_seen=\'$time\' ";
						$query .= "WHERE serial=\'$numeroserie\' AND name=\'$equipo\'";

						sql_do($query);
						p("scan:\t\t\t\tActualizamos:\t\t$numeroserie\t$equipo\t$objetivo\n") if($debug_scan);

					}

					# USUARIOS
					my @users = get_computer_users($objetivo);
					foreach (@users){
						if($_) {
							my %user = get_db_user($_);

							if(%user){
								foreach $key (sort(keys %user)) {
									associate_user_to_computer($numeroserie, $equipo, $key, $user{$key});
								}
							} else {
								my $complete_name = get_ad_complete_name($_);
								add_db_user($_, $complete_name);
								associate_user_to_computer($numeroserie, $equipo, $_, $complete_name);
							}
						}
					}
				} else {
					p("scan:\t\t\t\tProblemas con equipo $objetivo con S/N: $numeroserie. Falta equipo ($equipo) y/o sistema operativo($sistemaoperativo)\n") if($debug_scan);
				}
			} else {
				# p("scan:\t\t\t\tEquipo $objetivo no añadido. No se pudo sacar el número de serie.\n") if($debug_scan);
			}

			exit(0);

		} elsif($pid) {
			# Proceso padre
			$hijos++;
			sleep 1;
		} else {
			p("Cagada, no se pudo llamar a fork()\n");
		}
		
	}

	p("scan:\t\t\t\tScan para la red $network finalizado.\n") if($debug_scan);
	exit(0);
}

sub read_configuration {
	my $all = sql_selectall_arrayref("SELECT * FROM configuration");
				
	foreach my $row (@$all) {

		my ($key, $value) = @$row;

		switch ($key) {
			case "active_hours" { @active_hours = split(',', $value); }

			case "debug_get_serial_number"		{ $debug_get_serial_number		= $value; }
			case "debug_get_computer_name"		{ $debug_get_computer_name		= $value; }
			case "debug_get_model"			{ $debug_get_model			= $value; }
			case "debug_get_operating_system"	{ $debug_get_operating_system		= $value; }
			case "debug_get_db_user"		{ $debug_get_db_user			= $value; }
			case "debug_get_ad_complete_name"	{ $debug_get_ad_complete_name		= $value; }
			case "debug_add_db_user"		{ $debug_add_db_user			= $value; }
			case "debug_get_computer_users"		{ $debug_get_computer_users		= $value; }
			case "debug_associate_user_to_computer"	{ $debug_associate_user_to_computer	= $value; }
			case "debug_get_alive_ips"		{ $debug_get_alive_ips			= $value; }
			case "debug_scan"			{ $debug_scan				= $value; }
			case "debug_main"			{ $debug_main				= $value; }
		}
	}

}


sub create_db {

	if (! -e $rutadb){
		my $db = DBI->connect("dbi:SQLite:".$rutadb, "", "", {RaiseError => 1, AutoCommit => 1});
		$db->{sqlite_unicode} = 1;
		$db->do("CREATE TABLE computers (serial TEXT, name TEXT, model TEXT, os TEXT, last_ip TEXT, first_seen TEXT, last_seen TEXT)");
		$db->do("CREATE TABLE users (username TEXT, complete_name TEXT)");
		$db->do("CREATE TABLE computers_and_users (serial TEXT, computer_name TEXT, username TEXT, complete_name TEXT)");
		$db->do("CREATE TABLE networks (network TEXT, location TEXT)");
		$db->do("CREATE TABLE users_to_ignore (username TEXT)");

		$db->do("CREATE TABLE configuration (key TEXT, value TEXT)");
		my $default_config_sql = "";
		$default_config_sql .= "INSERT INTO configuration (key, value) VALUES ";

		$default_config_sql .= "('debug_get_serial_number', '0'),";
		$default_config_sql .= "('debug_get_computer_name','0'),";
		$default_config_sql .= "('debug_get_model','0'),";
		$default_config_sql .= "('debug_get_operating_system', '0'),";
		$default_config_sql .= "('debug_get_db_user', '0'),";
		$default_config_sql .= "('debug_get_ad_complete_name', '0'),";
		$default_config_sql .= "('debug_add_db_user', '0'),";
		$default_config_sql .= "('debug_get_computer_users', '0'),";
		$default_config_sql .= "('debug_associate_user_to_computer', '0'),";
		$default_config_sql .= "('debug_get_alive_ips', '0'),";
		$default_config_sql .= "('debug_scan', '1'),";
		$default_config_sql .= "('debug_main', '1'),";

		$default_config_sql .= "('active_hours', '10,13,17')";

		$db->do($default_config_sql);
		
		$db->disconnect;
		
		p("create_db:\t\t\tPor favor, edite $rutadb para añadir redes en las que escanear, su configuración, etcétera.\n");
		exit(0);
	}
}

sub enable_netcheck {
	system("mode con:cols=$columns lines=$lines_max");
	$textf->Text("");
	Win32::GUI::DoEvents();
	p("main:\t\t\t\tActivamos el escanner.\n\n") if($debug_main);
	$actived		= 1;
	$last_active_hour	= get_current_hour();
	Win32::GUI::Change($main, ( -title => "$tool_name - Active: $actived Last active hour: $last_active_hour Current hour: $h Active hours: @active_hours", ));
}

sub disable_netcheck {
	system("mode con:cols=$columns lines=$lines_min");
	p("main:\t\t\t\tDesactivado.\n") if($debug_main);
	$actived		= 0;
	Win32::GUI::Change($main, ( -title => "$tool_name - Active: $actived Last active hour: $last_active_hour Current hour: $h Active hours: @active_hours", ));
}

sub main {
	# Para crear la base de datos en el caso de que no existiese.
	create_db();

	read_configuration();

	# Inicia desactivado
	disable_netcheck();
	
	if(my $p = fork()) {
		$main->Show();
		Win32::GUI::Dialog();
		exit(0);
	} else {
		$last_h = -1;
		$h = get_current_hour();

		while("siempre a tope"){
			read_configuration();

			$h = get_current_hour();

			if($h != $last_h) {
				p("main:\t\t\t\tactive: $actived\tLast active hour: $last_active_hour\tCurrent hour: $h\tActive hours: @active_hours\n") if($debug_main);
				Win32::GUI::Change($main, ( -title => "$tool_name - Active: $actived Last active hour: $last_active_hour Current hour: $h Active hours: @active_hours", ));
				$last_h = $h;
			}

			if(!$actived){


				if( (grep ( /^$h$/, @active_hours )) && ($h != $last_active_hour )) {

					enable_netcheck();

					@users_to_ignore	= get_users_to_ignore();
					@networks		= get_all_networks();
					@networks		= shuffle(@networks);

					p("main:\t\t\t\tEscanearemos las siguientes redes: @networks\n\n") if($debug_main);
					my $hijos = 0;

					foreach(@networks){
						read_configuration();

						# Si los procesos hijo han superado el límite esperamos.
						if ($hijos >= $max_simultaneous_scans) {
							$pid = wait();
							$hijos--;
						}

						my $pid = fork();

						if(!$pid) {
							p("main:\t\t\t\tLlamamos a la función scan, argumento: $_\n") if($debug_main);
							scan($_);

						} elsif($pid) {
							$hijos++;
							sleep($seconds_to_wait_for_each_scan_call);

						} else {
							p("main:\t\t\t\tNo se ha podido hacer fork();");
							exit(1);
						}

					}

					p("main:\t\t\t\tNo hay más redes para escanear\n") if($debug_main);

					sleep 10;

					disable_netcheck();
				}
			}
			sleep 10;
		}
	}
}

main();
