#!/usr/bin/env python3
"""
Script d'automatisation COMPLET pour le script de pêche FiveM (qs-fisher / fiiiiish)
Version 5 : Correction des touches (CLIC DROIT pour charger/lancer, E pour interagir/morsure/décision)
et simulation de clavier/souris (pyautogui + keyboard) pour automatiser le processus.

PROCESSUS :
1. ATTENTE DE F11 (dans la fenêtre CMD/Console)
2. Vérification (Simulation : on suppose le joueur prêt)
3. Appuie sur 'E' pour activer la canne (ToggleFishingRod)
4. Recherche de l'eau (automatique dans le script FiveM, on attend le délai)
5. CHARGEMENT ET LANCEMENT : Maintient le CLIC DROIT (bouton 2) pendant ~1.1s (CHARGE_ANIM_DURATION) puis relâche (CastLineToWater)
6. Attente de la morsure (BiteWindow ~ 1.5s - 4.5s)
7. Ferrage : Appuie sur 'E' (InteractKey = 38) quand la morsure est détectée
8. Combat (Simulation souris/clavier selon le danger/progrès)
9. Décision : Garder/Relâcher via interface NUI (Appui sur 'E')
10. Nettoyage (Fin du processus)

AVERTISSEMENT :
- Ce script nécessite les bibliothèques : pip install keyboard pyautogui
- Il doit être lancé avec les privilèges administrateur (Windows) pour simuler les touches/souris dans le jeu FiveM.
- Le jeu FiveM doit être en mode fenêtré ou bordureless pour que la souris fonctionne bien.
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
    "INTERACT_KEY": "e",        # Touche pour activer la canne (E) / mordre (E) / décider (E)
    "CHARGE_KEY": "right",     # CLIC DROIT pour charger et lancer (Control ID 24)
    "FIGHT_LEFT": "a",          # Touche gauche (si configuré) ou mouvement souris
    "FIGHT_RIGHT": "d",         # Touche droite
    "MIN_BITE_TIME": 1.5,       # 1500ms
    "MAX_BITE_TIME": 4.5,       # 4500ms
    "BITE_WINDOW": 3.0,         # Fenêtre de morsure
    "UPDATE_RATE": 0.05,        # 50ms
    "MAX_ANGLE": 70.0,
    "F11_KEY": "f11",
    "CHARGE_ANIM_DURATION": 1.1 # CHARGE_ANIM_DURATION = 1100ms dans le script Lua
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
        """Charge la puissance et lance (Maintien CLIC DROIT puis relâchement)"""
        logging.info("Chargement de la puissance de lancer (Maintien CLIC DROIT)...")
        # Control ID 24 = Bouton Souris Droite (Right Mouse Button)
        pyautogui.mouseDown(button='right')
        
        # Simulation du cycle de charge (CHARGE_ANIM_DURATION = 1100ms)
        charge_time = CONFIG["CHARGE_ANIM_DURATION"]
        time.sleep(charge_time)
        
        pyautogui.mouseUp(button='right')
        logging.info(f"Lancement effectué (Puissance simulée : {charge_time:.2f}s)")

    def wait_for_bite(self):
        """Attente de la morsure (BiteWindow) puis appui sur E"""
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
        """Phase de combat (Simulation souris/clavier selon le danger/progrès)"""
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
                # Dans qs-fisher, on lâche la touche ou on bouge la souris
                break
            
            if progress >= 100:
                success = True
                break
            
            # Simulation du mouvement pour compenser le danger (si danger > 30, on bouge)
            if danger > 30:
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

    def decide_catch(self):
        """Décide de garder ou relâcher le poisson (Appui sur E)"""
        logging.info("Décision : Garder (Appui sur E)...")
        keyboard.press_and_release(CONFIG["INTERACT_KEY"])
        time.sleep(0.5)

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
        
        # 2. Charger et lancer (CLIC DROIT)
        self.charge_and_cast()
        
        # 3. Attendre la morsure et ferrer (E)
        if self.wait_for_bite():
            # 4. Combat
            self.start_fight()
            # 5. Décision (E)
            self.decide_catch()
        
        # 6. Nettoyage final (E)
        self.reset_state()
        
        logging.info("=== FIN DE L'AUTOMATISATION ===")

if __name__ == "__main__":
    if not HAS_LIBS:
        logging.error("Impossible de démarrer : installez 'keyboard' et 'pyautogui' (pip install keyboard pyautogui)")
        sys.exit(1)
        
    bot = FishAutomationBot()
    bot.run_full_process()
