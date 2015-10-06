# NetCheck
A simple tool to discover network computers, extract for each one its serial number, os version and more information. This tool is intended to be used in a corporative domain environment.

Every time that NetCheck discover a change in the name of a computer added, it will add another entry to maintain which
users worked with every configuration, operating system version of each one, ip addresses used, dates, etc.

This script must be run on a Windows machine. It will use wmic, dsget, dsquery and others Windows tools. Because some information only can be queried if the user running this script is administrator in the remote machine, it would be part of a AD group that be added to the local group Administrators on each domain computer.

IMPORTANT: It supposes that main storage devices like C: or D: are shared as C$ and D$. Edit this tool as needed.
