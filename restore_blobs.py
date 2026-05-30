import subprocess
import os

blobs = subprocess.check_output(['ls', '.git/lost-found/other/']).decode('utf-8').split()

for blob in blobs:
    path = f".git/lost-found/other/{blob}"
    with open(path, 'r') as f:
        try:
            content = f.read()
        except:
            continue
            
    if 'class LoginScreen' in content:
        with open('lib/src/features/auth_screen/login_screen.dart', 'w') as out:
            out.write(content)
            print("Restored login_screen.dart")
            
    elif 'class PendingApprovalScreen' in content:
        with open('lib/src/features/auth_screen/pending_screen.dart', 'w') as out:
            out.write(content)
            print("Restored pending_screen.dart")
            
    elif 'class MapLogic' in content:
        with open('lib/src/features/map_screen/map_logic.dart', 'w') as out:
            out.write(content)
            print("Restored map_logic.dart")
            
    elif 'class _DashboardHomeState' in content:
        if 't(context' not in content: # ensure we don't restore the broken one
            with open('lib/src/features/home/home_screen.dart', 'w') as out:
                out.write(content)
                print("Restored home_screen.dart")
                
    elif 'class _SlotCardState' in content:
        if 't(context' not in content:
            with open('lib/src/features/home/widgets/slot_card.dart', 'w') as out:
                out.write(content)
                print("Restored slot_card.dart")
                
    elif 'class DashboardStatsWidget' in content:
        if 't(context' not in content:
            with open('lib/src/features/home/widgets/dashboard_stats.dart', 'w') as out:
                out.write(content)
                print("Restored dashboard_stats.dart")
                
    elif 'class SlotSetupModal' in content:
        if 't(context' not in content:
            with open('lib/src/features/home/widgets/slot_setup_modal.dart', 'w') as out:
                out.write(content)
                print("Restored slot_setup_modal.dart")
                
    elif 'class QRScannerScreen' in content:
        if 't(context' not in content:
            with open('lib/src/features/qr_scanner_screen/qr_scanner_screen.dart', 'w') as out:
                out.write(content)
                print("Restored qr_scanner_screen.dart")
                
    elif 'class BottomNavigation' in content:
        if 't(context' not in content:
            with open('lib/src/features/app/ui/bottom_navigation.dart', 'w') as out:
                out.write(content)
                print("Restored bottom_navigation.dart")

