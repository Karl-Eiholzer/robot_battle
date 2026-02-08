#!/usr/bin/env python3
"""
Integration test script for Turn-Based Game API

Tests the complete game flow from creation to turn processing.
Can run against local or deployed API.

Usage:
    python test_api.py                          # Test local (http://localhost:8000)
    python test_api.py http://localhost:8000    # Test local (explicit)
    python test_api.py https://your-app.railway.app  # Test Railway deployment
"""

import requests
import json
import time
import sys
from typing import Dict, Any


class Colors:
    """ANSI color codes for terminal output"""
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    END = '\033[0m'
    BOLD = '\033[1m'


class APITester:
    """Integration tester for the game API"""

    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip('/')
        self.api_keys = {}  # player_id → api_key
        self.game_id = None
        self.player_ids = []
        self.tests_passed = 0
        self.tests_failed = 0

    def log_test(self, test_name: str):
        """Print test name"""
        print(f"\n{Colors.BOLD}{Colors.BLUE}[TEST]{Colors.END} {test_name}")

    def log_success(self, message: str):
        """Print success message"""
        print(f"{Colors.GREEN}✓{Colors.END} {message}")
        self.tests_passed += 1

    def log_error(self, message: str):
        """Print error message"""
        print(f"{Colors.RED}✗{Colors.END} {message}")
        self.tests_failed += 1

    def log_info(self, message: str):
        """Print info message"""
        print(f"{Colors.YELLOW}ℹ{Colors.END} {message}")

    def test_health_check(self) -> bool:
        """Test health check endpoint"""
        self.log_test("Health Check")

        try:
            response = requests.get(f"{self.base_url}/health")

            if response.status_code == 200:
                data = response.json()
                self.log_success(f"Health check passed: {json.dumps(data, indent=2)}")

                if data.get("redis"):
                    self.log_success("Redis connection is healthy")
                else:
                    self.log_error("Redis connection is NOT healthy")
                    return False

                return True
            else:
                self.log_error(f"Health check failed with status {response.status_code}")
                return False

        except Exception as e:
            self.log_error(f"Health check exception: {str(e)}")
            return False

    def test_create_game(self) -> bool:
        """Test game creation"""
        self.log_test("Create Game")

        payload = {
            "max_players": 4,
            "map_config": {
                "width": 10,
                "height": 10
            }
        }

        try:
            response = requests.post(
                f"{self.base_url}/game/create",
                json=payload
            )

            if response.status_code == 200:
                data = response.json()
                self.game_id = data["game_id"]
                creator_id = data["creator_player_id"]
                api_key = data["api_key"]

                self.player_ids.append(creator_id)
                self.api_keys[creator_id] = api_key

                self.log_success(f"Game created: {self.game_id}")
                self.log_info(f"Creator ID: {creator_id}")
                self.log_info(f"API Key: {api_key[:20]}...")
                self.log_info(f"State: {data['state']}")

                return True
            else:
                self.log_error(f"Create game failed with status {response.status_code}")
                self.log_error(f"Response: {response.text}")
                return False

        except Exception as e:
            self.log_error(f"Create game exception: {str(e)}")
            return False

    def test_join_game(self, player_name: str) -> bool:
        """Test joining a game"""
        self.log_test(f"Join Game as {player_name}")

        if not self.game_id:
            self.log_error("No game_id available")
            return False

        payload = {
            "player_name": player_name
        }

        try:
            response = requests.post(
                f"{self.base_url}/game/{self.game_id}/join",
                json=payload
            )

            if response.status_code == 200:
                data = response.json()
                player_id = data["player_id"]
                api_key = data["api_key"]

                self.player_ids.append(player_id)
                self.api_keys[player_id] = api_key

                self.log_success(f"{player_name} joined the game")
                self.log_info(f"Player ID: {player_id}")
                self.log_info(f"Current players: {data['current_players']}/{data['max_players']}")
                self.log_info(f"Game state: {data['state']}")

                return True
            else:
                self.log_error(f"Join game failed with status {response.status_code}")
                self.log_error(f"Response: {response.text}")
                return False

        except Exception as e:
            self.log_error(f"Join game exception: {str(e)}")
            return False

    def test_game_status(self, player_id: str) -> Dict[str, Any]:
        """Test getting game status"""
        self.log_test("Get Game Status")

        if not self.game_id:
            self.log_error("No game_id available")
            return None

        headers = {
            "X-API-Key": self.api_keys[player_id]
        }

        try:
            response = requests.get(
                f"{self.base_url}/game/{self.game_id}/status",
                headers=headers
            )

            if response.status_code == 200:
                data = response.json()
                self.log_success(f"Status retrieved")
                self.log_info(f"State: {data['state']}")
                self.log_info(f"Current turn: {data['current_turn']}")
                self.log_info(f"Moves submitted: {data['moves_submitted']}/{data['moves_required']}")
                return data
            else:
                self.log_error(f"Get status failed with status {response.status_code}")
                return None

        except Exception as e:
            self.log_error(f"Get status exception: {str(e)}")
            return None

    def test_submit_moves(self, player_id: str, turn: int) -> bool:
        """Test submitting moves"""
        self.log_test(f"Submit Moves (Player: {player_id[:12]}..., Turn: {turn})")

        if not self.game_id:
            self.log_error("No game_id available")
            return False

        # Create simple move
        payload = {
            "turn": turn,
            "moves": [
                {
                    "unit_id": f"{player_id}_unit_0",
                    "action": "move",
                    "target": [5, 5]
                }
            ]
        }

        headers = {
            "X-API-Key": self.api_keys[player_id]
        }

        try:
            response = requests.post(
                f"{self.base_url}/game/{self.game_id}/submit",
                json=payload,
                headers=headers
            )

            if response.status_code == 200:
                data = response.json()
                self.log_success(f"Moves submitted successfully")
                self.log_info(f"Moves: {data['moves_submitted']}/{data['moves_required']}")
                self.log_info(f"Processing: {data['processing']}")
                return True
            else:
                self.log_error(f"Submit moves failed with status {response.status_code}")
                self.log_error(f"Response: {response.text}")
                return False

        except Exception as e:
            self.log_error(f"Submit moves exception: {str(e)}")
            return False

    def test_poll_results(self, player_id: str, turn: int, timeout: int = 30) -> Dict[str, Any]:
        """Test polling for turn results with timeout"""
        self.log_test(f"Poll Results (Turn: {turn})")

        if not self.game_id:
            self.log_error("No game_id available")
            return None

        headers = {
            "X-API-Key": self.api_keys[player_id]
        }

        start_time = time.time()
        poll_count = 0

        while time.time() - start_time < timeout:
            poll_count += 1

            try:
                response = requests.get(
                    f"{self.base_url}/game/{self.game_id}/results?turn={turn}",
                    headers=headers
                )

                if response.status_code == 200:
                    data = response.json()

                    if data["ready"]:
                        self.log_success(f"Results ready after {poll_count} polls")
                        self.log_info(f"Updates: {len(data.get('updates', []))}")
                        self.log_info(f"Events: {len(data.get('events', []))}")
                        self.log_info(f"Next turn: {data.get('next_turn')}")
                        return data
                    else:
                        self.log_info(f"Polling... ({poll_count}) - State: {data.get('state')}")
                        time.sleep(2)  # Poll every 2 seconds
                else:
                    self.log_error(f"Poll failed with status {response.status_code}")
                    return None

            except Exception as e:
                self.log_error(f"Poll exception: {str(e)}")
                return None

        self.log_error(f"Polling timed out after {timeout} seconds")
        return None

    def run_full_game_flow(self):
        """Run complete game lifecycle test"""
        print(f"\n{Colors.BOLD}{'='*60}{Colors.END}")
        print(f"{Colors.BOLD}Testing API: {self.base_url}{Colors.END}")
        print(f"{Colors.BOLD}{'='*60}{Colors.END}")

        # Test 1: Health check
        if not self.test_health_check():
            self.log_error("Health check failed - aborting tests")
            return False

        # Test 2: Create game
        if not self.test_create_game():
            self.log_error("Game creation failed - aborting tests")
            return False

        # Test 3: Join game with 3 additional players
        for i in range(2, 5):
            if not self.test_join_game(f"Player{i}"):
                self.log_error(f"Player {i} join failed")
                return False

        time.sleep(1)  # Brief pause

        # Test 4: Check game status (should be "in_progress" now)
        status = self.test_game_status(self.player_ids[0])
        if not status or status["state"] != "in_progress":
            self.log_error(f"Game should be in_progress, but is: {status.get('state') if status else 'unknown'}")

        # Test 5: Submit moves for all players
        current_turn = status["current_turn"] if status else 0

        for i, player_id in enumerate(self.player_ids):
            if not self.test_submit_moves(player_id, current_turn):
                self.log_error(f"Move submission failed for player {i+1}")
                return False
            time.sleep(0.5)  # Small delay between submissions

        # Test 6: Poll for results
        results = self.test_poll_results(self.player_ids[0], current_turn)
        if not results:
            self.log_error("Failed to get turn results")
            return False

        # Test 7: Verify turn incremented
        final_status = self.test_game_status(self.player_ids[0])
        if final_status:
            if final_status["current_turn"] == current_turn + 1:
                self.log_success("Turn incremented correctly")
            else:
                self.log_error(f"Turn should be {current_turn + 1}, but is {final_status['current_turn']}")

        # Print summary
        print(f"\n{Colors.BOLD}{'='*60}{Colors.END}")
        print(f"{Colors.BOLD}Test Summary{Colors.END}")
        print(f"{Colors.BOLD}{'='*60}{Colors.END}")
        print(f"{Colors.GREEN}Passed: {self.tests_passed}{Colors.END}")
        print(f"{Colors.RED}Failed: {self.tests_failed}{Colors.END}")

        if self.tests_failed == 0:
            print(f"\n{Colors.GREEN}{Colors.BOLD}✓ ALL TESTS PASSED{Colors.END}")
            return True
        else:
            print(f"\n{Colors.RED}{Colors.BOLD}✗ SOME TESTS FAILED{Colors.END}")
            return False


def main():
    """Main entry point"""
    # Get URL from command line or use default
    if len(sys.argv) > 1:
        base_url = sys.argv[1]
    else:
        base_url = "http://localhost:8000"

    # Create tester and run tests
    tester = APITester(base_url)
    success = tester.run_full_game_flow()

    # Exit with appropriate code
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
