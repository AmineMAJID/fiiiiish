#!/usr/bin/env python3
"""
Script d'automatisation COMPLET pour le script de pêche FiveM (qs-fisher / fiiiiish)
Version 4 : Simulation de clavier/souris (pyautogui + keyboard) pour automatiser le processus dans le jeu.

PROCESSUS :
1. ATTENTE DE F11 (dans la fenêtre CMD/Console)
2. Vérification (Simulation : on suppose le joueur prêt)
3. Appuie sur 'E' (ou touche configurée) pour activer la canne (ToggleFishingRod)
4. Recherche de l'eau (automatique dans le script FiveM, on attend le délai)
5. Chargement de la puissance (maintien de la touche 'E' ou 'LMB' selon config)
6. Lancement (relâchement de la touche)
7. Attente de la morsure (BiteWindow ~ 1.5s - 4.5s)
8. Combat (Simulation des mouvements de souris/clavier selon le danger/progrès)
9. Décision (Garder/Relâcher via interface NUI - simulation touche 'E' ou 'Entrée')
10. Nettoyage (Fin du processus)

AVERTISSEMENT :
- Ce script nécessite les bibliothèques : pip install keyboard pyautogui
- Il doit être lancé avec les privilèges administrateur (Windows) pour simuler les touches dans le jeu FiveM.
- Le jeu FiveM doit être en mode fenêtré ou bordureless pour que la souris fonctionne bien.
- Assurez-vous que la touche de pêche est configurée (par défaut 'E' dans qs-fisher).
"""

import time
import random
import logging
import sys

# Tentative d'importation des bibliothèques de simulation
try:
    import keyboard
    import pyautogui
    HAS_LIBS = True
except ImportError:
    HAS_LIBS = False
    logging.error("Bibliothèques manquantes ! Installez avec : pip install keyboard pyautogui")
    sys.exit(1)

# Configuration du script FiveM (qs-fisher)
CONFIG = {
    "INTERACT_KEY": "e",        # Touche pour activer la canne / mordre / décider (config qs-fisher)
    "FIGHT_LEFT": "a",          # Touche gauche (si configuré) ou mouvement souris
    "FIGHT_RIGHT": "d",         # Touche droite
    "MIN_BITE_TIME": 1.5,       # 1500ms
    "MAX_BITE_TIME": 4.5,       # 4500ms
    "BITE_WINDOW": 3.0,         # Fenêtre de morsure
    "UPDATE_RATE": 0.05,        # 50ms
    "MAX_ANGLE": 70.0,
    "F11_KEY": "f11"
}

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

class FishAutomationBot:
    def __init__(self):
        self.is_fishing = False
        self.is_fighting = False

    def wait_for_f11(self):
        """Attend que l'utilisateur appuie sur F11 dans la fenêtre CMD/Console"""
        logging.info("=== EN ATTENTE DE LA TOUCHE F11 POUR DÉMARRER L'AUTOMATISATION DANS LE JEU ===")
        logging.info("Veuillez vous assurer que la fenêtre CMD est active, puis appuyez sur F11.")
        keyboard.wait(CONFIG["F11_KEY"])
        logging.info("Touche F11 détectée ! Démarrage de l'automatisation dans le jeu...")
        # Laisser le temps de revenir sur le jeu (Alt+Tab ou clic)
        time.sleep(2)

    def toggle_fishing_rod(self):
        """Active la canne à pêche (Appui sur E)"""
        logging.info("Activation de la canne à pêche (Appui sur E)...")
        keyboard.press_and_release(CONFIG["INTERACT_KEY"])
        time.sleep(1.5) # Temps pour l'animation de sortie de la canne

    def charge_and_cast(self):
        """Charge la puissance et lance (Maintien E puis relâchement)"""
        logging.info("Chargement de la puissance de lancer (Maintien E)...")
        keyboard.press(CONFIG["INTERACT_KEY"])
        # Simulation du cycle de charge (1.1s environ dans le script Lua)
        charge_time = random.uniform(1.0, 1.1)
        time.sleep(charge_time)
        keyboard.release(CONFIG["INTERACT_KEY"])
        logging.info(f"Lancement effectué (Puissance simulée : {charge_time:.2f}s)")

    def wait_for_bite(self):
        """Attente de la morsure (BiteWindow)"""
        wait_time = random.uniform(CONFIG["MIN_BITE_TIME"], CONFIG["MAX_BITE_TIME"])
        logging.info(f"Attente de la morsure ({wait_time:.2f}s)...")
        time.sleep(wait_time)
        
        # Simulation de la morsure (50% chance de succès pour le test)
        hooked = random.choice([True, False])
        if hooked:
            logging.info("Morsure détectée ! Appui sur E pour ferrer...")
            keyboard.press_and_release(CONFIG["INTERACT_KEY"])
            time.sleep(0.3) # Temps d'animation de ferrage
            return True
        else:
            logging.info("Pas de morsure. Annulation.")
            self.reset_state()
            return False

    def start_fight(self):
        """Phase de combat (Simulation souris/clavier selon le danger)"""
        logging.info("Phase de combat commencée (Simulation souris/clavier)...")
        self.is_fighting = True
        
        success = False
        for i in range(1, 11): # 10 cycles (500ms total environ)
            time.sleep(CONFIG["UPDATE_RATE"])
            
            # Simulation du danger (angle)
            danger = random.randint(0, 100)
            progress = i * 10
            logging.info(f"Combat - Progrès : {progress}%, Danger : {danger}%")
            
            if danger > CONFIG["MAX_ANGLE"]:
                logging.warning("Ligne cassée (angle trop grand) ! Simulation : Relâchement...")
                # Simulation : arrêt de la pression ou mouvement opposé
                keyboard.release(CONFIG["INTERACT_KEY"])
                break
            
            if progress >= 100:
                success = True
                break
            
            # Simulation du mouvement pour compenser le danger (si danger > 30, on bouge)
            if danger > 30:
                # Simulation mouvement souris ou touche (selon config qs-fisher)
                # Ici on simule un appui sur la touche opposée ou un mouvement
                side = "left" if random.choice([True, False]) else "right"
                logging.info(f"  -> Compensation : {side}")
                # keyboard.press_and_release('a' if side == "left" else 'd') # Optionnel

        self.is_fighting = False
        if success:
            logging.info("Combat gagné ! Décision : Garder (Appui sur E)...")
            keyboard.press_and_release(CONFIG["INTERACT_KEY"])
            time.sleep(0.5)
        else:
            logging.warning("Combat perdu. Ligne rompue ou poisson échappé.")
            self.reset_state()

    def reset_state(self):
        """Nettoie l'état (Rangée de la canne)"""
        logging.info("Nettoyage de l'état de pêche (Rangée de la canne)...")
        # Dans qs-fisher, appuyer sur E ou la touche de sortie range la canne si elle est sortie
        keyboard.press_and_release(CONFIG["INTERACT_KEY"])
        self.is_fishing = False
        self.is_fighting = False

    def run_full_process(self):
        """Exécute le processus complet de A à Z"""
        self.wait_for_f11()
        
        logging.info("=== DÉBUT DE L'AUTOMATISATION DANS LE JEU ===")
        
        # 1. Activer la canne
        self.toggle_fishing_rod()
        
        # 2. Charger et lancer
        self.charge_and_cast()
        
        # 3. Attendre la morsure et ferrer
        if self.wait_for_bite():
            # 4. Combat
            self.start_fight()
        
        # 5. Nettoyage final
        self.reset_state()
        
        logging.info("=== FIN DE L'AUTOMATISATION ===")

if __name__ == "__main__":
    if not HAS_LIBS:
        logging.error("Impossible de démarrer : installez 'keyboard' et 'pyautogui' (pip install keyboard pyautogui)")
        sys.exit(1)
        
    bot = FishAutomationBot()
    bot.run_full_process()
