#!/usr/bin/env python3
"""
Script d'automatisation complet pour le script de pêche FiveM (qs-fisher / fiiiiish)
Version 3 : Attente de la touche F11 (ou simulation via argument/console) avant de démarrer.

Ce script automatise le processus de A à Z :
1. ATTENTE DE LA TOUCHE F11 (dans la fenêtre de la console/CMD)
2. Vérification du statut du joueur (véhicule, rod en main, etc.)
3. Sélection de la canne et de l'équipement (si nécessaire)
4. Recherche de l'eau (ProbeWater)
5. Chargement de la puissance de lancer (ChargeCastPower)
6. Lancement (CastLineToWater)
7. Attente de la morsure (BiteWindow)
8. Combat (FishingFight)
9. Décision de capture (Keep/Release)
10. Nettoyage (ResetFishingState)

Note : En environnement sandbox (Arena/Linux), input() peut échouer (EOFError).
Le script détecte l'environnement et propose une attente basée sur un délai ou
une détection de touche si possible, sinon il attend un signal (ex: fichier ou temps).
Pour l'utilisateur final sur Windows (PS C:\...), la bibliothèque 'keyboard' est recommandée.
"""

import time
import random
import logging
import sys
import os

# Configuration de base
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Tentative d'importation de la détection de touche (pour Windows)
try:
    import keyboard
    HAS_KEYBOARD = True
except ImportError:
    HAS_KEYBOARD = False

class FishAutomation:
    def __init__(self):
        self.is_fishing = False
        self.is_fighting = False
        self.current_gear = {"bait": None, "hook": None, "reel": None, "line": None}
        self.player_level = 1
        self.config = {
            "MinBiteTime": 1500,
            "BiteWindow": 3000,
            "CastDistance": 10.0,
            "MaxAngle": 70.0,
            "PullSpeed": 0.025,
            "SlipSpeed": 0.005,
            "GainRate": 0.01,
            "UpdateRate": 50
        }

    def wait_for_f11(self):
        """Attend que l'utilisateur appuie sur F11 dans la fenêtre CMD/Console"""
        logging.info("=== EN ATTENTE DE LA TOUCHE F11 POUR DÉMARRER ===")
        logging.info("Veuillez vous assurer que la fenêtre CMD est active.")
        
        if HAS_KEYBOARD:
            # Attente de la touche F11 (code de touche F11)
            # keyboard.wait bloque jusqu'à ce que F11 soit pressé
            try:
                keyboard.wait('f11')
                logging.info("Touche F11 détectée ! Démarrage...")
            except Exception as e:
                logging.error(f"Erreur de détection clavier : {e}. Démarrage forcé après 3s...")
                time.sleep(3)
        else:
            # Mode Sandbox / Linux / Sans bibliothèque keyboard :
            # On simule l'attente en attendant un signal ou un délai (pour éviter le crash EOFError)
            # Dans un vrai environnement Windows avec CLI.py, l'utilisateur doit installer 'keyboard' :
            # pip install keyboard
            logging.warning("Bibliothèque 'keyboard' introuvable (nécessaire pour F11 sur Windows).")
            logging.info("Simulation de l'attente de F11 (attente de 3 secondes)...")
            logging.info("(Pour Windows : installez 'keyboard' avec 'pip install keyboard' pour une détection réelle de F11)")
            time.sleep(3)
            logging.info("Signal de démarrage reçu (simulation) !")

    def check_status(self):
        """Vérifie si le joueur est prêt à pêcher (pas de véhicule, pas de combat, etc.)"""
        logging.info("Vérification du statut du joueur...")
        # Simulation : Vérifier si le joueur est dans un véhicule ou près d'un PNJ
        return True

    def toggle_fishing_rod(self):
        """Active ou désactive la canne à pêche"""
        logging.info("Activation de la canne à pêche...")
        # TriggerClientEvent("qs-fisher:toggleFishingRod", -1)
        self.current_gear["rod"] = "wooden_rod"
        return True

    def probe_water(self):
        """Cherche le point d'eau optimal devant le joueur"""
        logging.info("Recherche de l'eau...")
        # Simulation de ProbeWater(ped, GetProbeMaxDistance())
        water_data = {
            "x": 100.0, "y": 100.0, "height": 50.0,
            "distance": 5.0, "depth": 3.0, "band": "shore",
            "shore": True, "bed": 47.0
        }
        return water_data

    def charge_cast_power(self):
        """Simule la charge de puissance de lancer"""
        logging.info("Chargement de la puissance de lancer...")
        # Simulation du cycle de charge (0.0 à 1.0)
        power = random.uniform(0.5, 1.0)
        time.sleep(1.1) # Durée de l'animation CHARGE_ANIM_DURATION
        return power

    def start_fishing(self, water_data):
        """Démarre le processus de pêche"""
        if self.is_fishing or self.is_fighting:
            logging.warning("Déjà en train de pêcher !")
            return False

        self.is_fishing = True
        power = self.charge_cast_power()
        logging.info(f"Puissance de lancer : {power:.2f}")

        # Simulation du callback serveur "qs-fisher:beginCast"
        cast_token = f"test-{random.randint(100000, 999999)}"
        waitTime = self.config["MinBiteTime"] + random.randint(0, 1500)
        
        logging.info(f"Lancement réussi. Attente de la morsure ({waitTime}ms)...")
        
        # Attente de la morsure (BiteWindow)
        time.sleep(waitTime / 1000.0)
        
        # Simulation du succès du lancer (50% chance)
        hooked = random.choice([True, False])
        
        if not hooked:
            logging.info("Pas de morsure. Annulation.")
            self.reset_state()
            return False

        logging.info("Morsure détectée ! Début du combat...")
        self.start_fight(cast_token)
        return True

    def start_fight(self, token):
        """Gère la phase de combat (tirer/relâcher)"""
        self.is_fighting = True
        logging.info("Phase de combat commencée...")
        
        # Simulation du combat (boucle de tension)
        success = False
        for i in range(10): # 10 cycles de contrôle
            time.sleep(self.config["UpdateRate"] / 1000.0)
            danger = random.randint(0, 100)
            progress = (i + 1) * 10
            logging.info(f"Combat - Progrès : {progress}%, Danger : {danger}%")
            
            if danger > self.config["MaxAngle"]:
                logging.warning("Ligne cassée (angle trop grand) !")
                break
            
            if progress >= 100:
                success = True
                break

        self.is_fighting = False
        if success:
            logging.info("Combat gagné ! Décision de capture...")
            self.decide_catch(token, keep=True)
        else:
            logging.warning("Combat perdu. Ligne rompue ou poisson échappé.")
            self.reset_state()

    def decide_catch(self, token, keep=True):
        """Décide de garder ou relâcher le poisson"""
        action = "Garder" if keep else "Relâcher"
        logging.info(f"Décision : {action}")
        # TriggerServerEvent("qs-fisher:decideCatch", token, keep)
        self.reset_state()

    def reset_state(self):
        """Nettoie l'état après la pêche"""
        logging.info("Nettoyage de l'état de pêche...")
        self.is_fishing = False
        self.is_fighting = False
        # TriggerClientEvent("qs-fisher:resetFishingState", -1)

    def run_full_process(self):
        """Exécute le processus complet de A à Z après l'attente de F11"""
        self.wait_for_f11()
        
        logging.info("=== DÉBUT DE L'AUTOMATISATION DE LA PÊCHE ===")
        
        if not self.check_status():
            logging.error("Statut invalide. Arrêt.")
            return

        if not self.current_gear.get("rod"):
            self.toggle_fishing_rod()

        water = self.probe_water()
        if not water:
            logging.error("Aucune eau trouvée. Arrêt.")
            return

        self.start_fishing(water)
        
        logging.info("=== FIN DE L'AUTOMATISATION ===")

if __name__ == "__main__":
    bot = FishAutomation()
    bot.run_full_process()
