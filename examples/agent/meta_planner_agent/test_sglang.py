#!/usr/bin/env python3
"""
Script to test sglang server with retry logic
"""

import argparse
import requests
import json
import time
import sys


def test_sglang_server_once(
    host, port, test_prompt="你好，请用一句话介绍你自己。", timeout=30, max_tokens=100, temperature=0.7
):
    """Test sglang server with a simple question (single attempt)"""
    base_url = f"http://{host}:{port}"

    # Check if server is running
    try:
        # Try to connect to the server
        health_url = f"{base_url}/health"
        try:
            response = requests.get(health_url, timeout=5)
            print(f"✅ Server is reachable (health check: {response.status_code})")
        except requests.exceptions.RequestException:
            print("⚠️  Health endpoint not available, trying direct API call...")
    except Exception as e:
        print(f"⚠️  Health check failed: {e}")

    # Test with OpenAI-compatible API
    api_url = f"{base_url}/v1/chat/completions"

    payload = {
        "model": "default",
        "messages": [{"role": "user", "content": test_prompt}],
        "temperature": temperature,
        "max_tokens": max_tokens,
    }

    print(f"Sending request to {api_url}...")
    print(f"Payload: {json.dumps(payload, indent=2, ensure_ascii=False)}")
    print("")

    try:
        start_time = time.time()
        response = requests.post(api_url, json=payload, headers={"Content-Type": "application/json"}, timeout=timeout)
        elapsed_time = time.time() - start_time

        print(f"Response status: {response.status_code}")
        print(f"Response time: {elapsed_time:.2f} seconds")
        print("")

        if response.status_code == 200:
            result = response.json()
            print("✅ Server responded successfully!")
            print("")
            print("Response:")
            print(json.dumps(result, indent=2, ensure_ascii=False))
            print("")

            # Extract the actual response text
            if "choices" in result and len(result["choices"]) > 0:
                message = result["choices"][0].get("message", {})
                content = message.get("content", "")
                if content:
                    print("=" * 60)
                    print("Model Response:")
                    print(content)
                    print("=" * 60)
                    print("")
                    print("✅ Test PASSED: Model can generate responses")
                    return True
                else:
                    print("❌ Test FAILED: No content in response")
                    return False
            else:
                print("❌ Test FAILED: Invalid response format")
                return False
        else:
            print(f"❌ Test FAILED: Server returned status {response.status_code}")
            print(f"Response: {response.text}")
            return False

    except requests.exceptions.ConnectionError:
        print(f"❌ Cannot connect to server at {base_url}")
        return False
    except requests.exceptions.Timeout:
        print(f"❌ Request timed out after {timeout} seconds")
        return False
    except Exception as e:
        print(f"❌ Test FAILED: {type(e).__name__}: {e}")
        import traceback

        traceback.print_exc()
        return False


def test_sglang_server(
    host,
    port,
    initial_wait=180,
    retry_interval=60,
    test_prompt="你好，请用一句话介绍你自己。",
    timeout=30,
    max_tokens=100,
    temperature=0.7,
    verbose=False,
):
    """Test sglang server with retry logic"""
    base_url = f"http://{host}:{port}"

    print(f"Testing sglang server at {base_url}")
    print(f"Test prompt: {test_prompt}")
    if verbose:
        print(f"Configuration:")
        print(f"  - Timeout: {timeout}s")
        print(f"  - Max tokens: {max_tokens}")
        print(f"  - Temperature: {temperature}")
    print("")

    # First attempt: wait initial_wait seconds
    print(f"⏳ Waiting {initial_wait} seconds for server to be ready (first attempt)...")
    time.sleep(initial_wait)
    print("")

    attempt = 1
    while True:
        print(f"Attempt {attempt}: Testing connection...")
        print("-" * 60)

        success = test_sglang_server_once(host, port, test_prompt, timeout, max_tokens, temperature)

        if success:
            return True

        # If failed, wait and retry
        attempt += 1
        print("-" * 60)
        print(f"❌ Attempt {attempt - 1} failed. Waiting {retry_interval} seconds before retry...")
        print("")
        time.sleep(retry_interval)


def parse_args():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(
        description="Test sglang server with retry logic",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Test with default settings (port 30000, localhost, wait 180s initially, retry every 60s)
  python test_sglang.py

  # Test with custom port
  python test_sglang.py --port 30001

  # Test with custom host and port
  python test_sglang.py --host 192.168.1.100 --port 30000

  # Test with custom wait times
  python test_sglang.py --initial-wait 120 --retry-interval 30
        """,
    )

    parser.add_argument(
        "--host",
        type=str,
        default="localhost",
        help="Server host address (default: localhost)",
    )

    parser.add_argument(
        "--port",
        type=int,
        default=30000,
        help="Server port number (default: 30000)",
    )

    parser.add_argument(
        "--initial-wait",
        type=int,
        default=180,
        metavar="SECONDS",
        help="Initial wait time in seconds before first test attempt (default: 180)",
    )

    parser.add_argument(
        "--retry-interval",
        type=int,
        default=60,
        metavar="SECONDS",
        help="Wait time in seconds between retry attempts (default: 60)",
    )

    parser.add_argument(
        "--timeout",
        type=int,
        default=30,
        metavar="SECONDS",
        help="Request timeout in seconds (default: 30)",
    )

    parser.add_argument(
        "--max-tokens",
        type=int,
        default=100,
        help="Maximum tokens to generate in test request (default: 100)",
    )

    parser.add_argument(
        "--temperature",
        type=float,
        default=0.7,
        help="Temperature for test request (default: 0.7)",
    )

    parser.add_argument(
        "--test-prompt",
        type=str,
        default="你好，请用一句话介绍你自己。",
        help="Test prompt to send to the server (default: 你好，请用一句话介绍你自己。)",
    )

    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Enable verbose output",
    )

    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()

    success = test_sglang_server(
        host=args.host,
        port=args.port,
        initial_wait=args.initial_wait,
        retry_interval=args.retry_interval,
        test_prompt=args.test_prompt,
        timeout=args.timeout,
        max_tokens=args.max_tokens,
        temperature=args.temperature,
        verbose=args.verbose,
    )
    sys.exit(0 if success else 1)
