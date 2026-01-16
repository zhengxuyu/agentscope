"""The planner agent example."""

import asyncio
import json
import os
from argparse import ArgumentParser
from pathlib import Path

from tool import create_worker

from agentscope.agent import ReActAgent
from agentscope.formatter import DashScopeChatFormatter, OpenAIChatFormatter
from agentscope.message import (
    Msg,
    TextBlock,
    ImageBlock,
    AudioBlock,
    VideoBlock,
    URLSource,
)
from agentscope.model import DashScopeChatModel, OpenAIChatModel
from agentscope.plan import PlanNotebook
from agentscope.tool import Toolkit
from datasets import load_dataset
from huggingface_hub import snapshot_download


async def process_sample(
    sample_idx: int,
    sample: dict,
    data_dir: str,
    planner: ReActAgent,
    result_dir: Path | None = None,
) -> dict:
    """Process a single GAIA sample.

    Args:
        sample_idx: Index of the sample in the dataset
        sample: The sample data from the dataset
        data_dir: Directory where the dataset is stored
        planner: The ReActAgent instance to use
        result_dir: Directory to save results (optional)

    Returns:
        dict: Result containing sample_idx, question, answer, and metadata
    """
    # Get the question text
    question = sample.get("Question") or sample.get("question") or ""

    # Get file information from the dataset
    file_name = sample.get("file_name") or sample.get("file")
    file_path = sample.get("file_path") or sample.get("file")

    # Resolve file path relative to data_dir if it's a relative path
    if file_path and not os.path.isabs(file_path):
        file_path = os.path.join(data_dir, file_path)

    # Build content blocks: text + media
    content_blocks = []

    # Add text block with question
    if question:
        content_blocks.append(
            TextBlock(
                type="text",
                text=question,
            )
        )

    # Add image/media blocks if file_path exists
    if file_path:
        # Determine media type based on file extension
        file_ext = file_path.lower().split(".")[-1] if "." in file_path else ""

        if file_ext in ["jpg", "jpeg", "png", "gif", "webp", "bmp"]:
            # Image file
            content_blocks.append(
                ImageBlock(
                    type="image",
                    source=URLSource(
                        type="url",
                        url=file_path,
                    ),
                )
            )
        elif file_ext in ["mp3", "wav", "ogg", "m4a", "aac"]:
            # Audio file
            content_blocks.append(
                AudioBlock(
                    type="audio",
                    source=URLSource(
                        type="url",
                        url=file_path,
                    ),
                )
            )
        elif file_ext in ["mp4", "avi", "mov", "mkv", "webm"]:
            # Video file
            content_blocks.append(
                VideoBlock(
                    type="video",
                    source=URLSource(
                        type="url",
                        url=file_path,
                    ),
                )
            )
        elif file_ext in ["xlsx", "xls", "csv", "pdf", "docx", "doc", "txt"]:
            # Document files - try using ImageBlock as some vision models can process documents
            # Also add file info to text for reference with full path
            if content_blocks and len(content_blocks) > 0 and content_blocks[0].get("type") == "text":
                # Update the existing text block to include file information with full path
                existing_text = content_blocks[0].get("text", question) or question
                file_info = (
                    f"{existing_text}\n\n"
                    f"Attached file: {file_name or os.path.basename(file_path)}\n"
                    f"File path: {file_path}"
                )
                content_blocks[0] = TextBlock(
                    type="text",
                    text=file_info,
                )
            elif not content_blocks:
                # No text block yet, create one with file info including full path
                file_info_text = f"Attached file: {file_name or os.path.basename(file_path)}\nFile path: {file_path}"
                if question:
                    file_info_text = f"{question}\n\n{file_info_text}"
                content_blocks.append(
                    TextBlock(
                        type="text",
                        text=file_info_text,
                    )
                )
            # Try using ImageBlock for document files (some vision models support this)
            content_blocks.append(
                ImageBlock(
                    type="image",
                    source=URLSource(
                        type="url",
                        url=file_path,
                    ),
                )
            )
        else:
            # Unknown file type - add file path to text with full path
            if content_blocks and len(content_blocks) > 0 and content_blocks[0].get("type") == "text":
                # Update the existing text block to include file information with full path
                existing_text = content_blocks[0].get("text", question) or question
                file_info = (
                    f"{existing_text}\n\n"
                    f"Attached file: {file_name or os.path.basename(file_path)}\n"
                    f"File path: {file_path}"
                )
                content_blocks[0] = TextBlock(
                    type="text",
                    text=file_info,
                )
            elif not content_blocks:
                # No text block yet, create one with file info including full path
                file_info_text = f"Attached file: {file_name or os.path.basename(file_path)}\nFile path: {file_path}"
                if question:
                    file_info_text = f"{question}\n\n{file_info_text}"
                content_blocks.append(
                    TextBlock(
                        type="text",
                        text=file_info_text,
                    )
                )

    # Create message with content blocks
    if content_blocks:
        msg = Msg(name="user", content=content_blocks, role="user")
    else:
        # Fallback to text-only if no blocks created
        msg = Msg(name="user", content=question or "No question found", role="user")

    print(f"[Sample {sample_idx}] Question: {question}")
    if file_name:
        print(f"[Sample {sample_idx}] File name: {file_name}")
    if file_path:
        print(f"[Sample {sample_idx}] File path: {file_path}")

    try:
        # Debug: Check available tools before calling planner
        available_tools = planner.toolkit.get_json_schemas()
        print(f"[Sample {sample_idx}] Available tools: {[t.get('function', {}).get('name') for t in available_tools]}")

        msg = await planner(msg)

        # Debug: Check message content blocks
        all_blocks = msg.get_content_blocks()
        print(f"[Sample {sample_idx}] Total content blocks: {len(all_blocks)}")
        for i, block in enumerate(all_blocks):
            block_type = block.get("type", "unknown")
            print(f"[Sample {sample_idx}] Block {i}: type={block_type}")
            if block_type == "tool_use":
                print(f"[Sample {sample_idx}]   Tool name: {block.get('name')}")
                print(f"[Sample {sample_idx}]   Tool input: {block.get('input')}")

        # Debug: Check if message contains tool_use blocks
        tool_use_blocks = msg.get_content_blocks("tool_use")
        print(f"[Sample {sample_idx}] Tool use blocks count: {len(tool_use_blocks)}")
        for i, tool_block in enumerate(tool_use_blocks):
            print(f"[Sample {sample_idx}] Tool {i}: {tool_block.get('name')}")

        answer = msg.get_text_content()
        print(f"[Sample {sample_idx}] Answer length: {len(answer) if answer else 0}")
        if answer:
            print(f"[Sample {sample_idx}] Answer preview: {answer[:500]}...")

        result = {
            "sample_idx": sample_idx,
            "question": question,
            "file_name": file_name,
            "file_path": file_path,
            "answer": answer,
            "success": True,
        }
    except Exception as e:
        print(f"[Sample {sample_idx}] Error: {str(e)}")
        result = {
            "sample_idx": sample_idx,
            "question": question,
            "file_name": file_name,
            "file_path": file_path,
            "answer": None,
            "error": str(e),
            "success": False,
        }

    # Save result if result_dir is provided
    if result_dir:
        result_dir.mkdir(parents=True, exist_ok=True)
        result_file = result_dir / f"sample_{sample_idx:05d}.json"
        with open(result_file, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2, ensure_ascii=False)
        print(f"[Sample {sample_idx}] Result saved to {result_file}")

    return result


async def main() -> None:
    """The main function."""
    parser = ArgumentParser(description="Run GAIA benchmark test")
    parser.add_argument(
        "--sample_idx",
        type=int,
        default=None,
        help="Index of the sample to test (0-based). If not specified, test all samples.",
    )
    parser.add_argument(
        "--start_idx",
        type=int,
        default=0,
        help="Start index for batch testing (default: 0)",
    )
    parser.add_argument(
        "--end_idx",
        type=int,
        default=None,
        help="End index for batch testing (exclusive). If not specified, test all remaining samples.",
    )
    parser.add_argument(
        "--result_dir",
        type=str,
        default="./results/gaia",
        help="Directory to save results (default: ./results/gaia)",
    )
    parser.add_argument(
        "--data_dir",
        type=str,
        default=None,
        help="Directory where GAIA dataset is cached. If not specified, will download automatically.",
    )
    parser.add_argument(
        "--model_type",
        type=str,
        choices=["dashscope", "sglang", "openai"],
        default="dashscope",
        help="Model type to use: dashscope, sglang, or openai (default: dashscope)",
    )
    parser.add_argument(
        "--model_name",
        type=str,
        default=None,
        help=(
            "Model name. For dashscope: qwen3-max (default). "
            "For sglang/openai: model name (e.g., Qwen/Qwen2.5-8B-Instruct)"
        ),
    )
    parser.add_argument(
        "--api_base",
        type=str,
        default=None,
        help="API base URL for sglang/openai models (e.g., http://localhost:30000/v1)",
    )
    parser.add_argument(
        "--api_key",
        type=str,
        default=None,
        help=(
            "API key. For dashscope: DASHSCOPE_API_KEY env var. "
            "For sglang/openai: OPENAI_API_KEY env var or this argument."
        ),
    )
    args = parser.parse_args()

    # Download or load dataset
    try:
        if args.data_dir:
            data_dir = args.data_dir
            print(f"Using local data directory: {data_dir}")
        else:
            print("Downloading GAIA dataset from Hugging Face...")
            try:
                data_dir = snapshot_download(repo_id="gaia-benchmark/GAIA", repo_type="dataset")
                print(f"Dataset downloaded to: {data_dir}")
            except Exception as e:
                print(f"❌ Failed to download dataset: {e}")
                print("\nPossible reasons:")
                print("1. Network connection issue - check your internet connection")
                print("2. Need to accept access terms at: https://huggingface.co/datasets/gaia-benchmark/GAIA")
                print("3. Authentication issue - run: hf auth login")
                print("4. Firewall or proxy blocking the connection")
                print("\nYou can use --data_dir to specify a local dataset directory instead.")
                raise

        print(f"Loading dataset from: {data_dir}")
        ds = load_dataset(data_dir, "2023_all", split="validation")
        total_samples = len(ds)

        if total_samples == 0:
            print("❌ Warning: Dataset loaded but contains 0 samples!")
            print(f"Data directory: {data_dir}")
            print("Please check:")
            print("1. If using --data_dir, verify the directory contains valid GAIA dataset files")
            print("2. If downloading, the download may have failed or been incomplete")
            raise ValueError("Dataset contains 0 samples")

        print(f"✅ Successfully loaded dataset with {total_samples} samples")
    except Exception as e:
        print(f"❌ Error loading dataset: {e}")
        import traceback

        traceback.print_exc()
        raise

    # Connect to the studio for better visualization (optional)
    # import agentscope
    # agentscope.init(
    #     project="meta_planner_agent",
    #     studio_url="http://localhost:3000",
    # )

    # Configure model based on model_type
    if args.model_type == "dashscope":
        model_name = args.model_name or "qwen3-max"
        api_key = args.api_key or os.environ.get("DASHSCOPE_API_KEY")
        if not api_key:
            raise ValueError(
                "DASHSCOPE_API_KEY environment variable or --api_key argument is required for dashscope model"
            )
        model = DashScopeChatModel(
            model_name=model_name,
            api_key=api_key,
        )
        formatter = DashScopeChatFormatter()
    elif args.model_type in ["sglang", "openai"]:
        # For sglang/openai, use OpenAIChatModel with custom base_url
        model_name = args.model_name or "Qwen/Qwen2.5-8B-Instruct"
        api_base = args.api_base or os.environ.get("OPENAI_API_BASE", "http://localhost:30000/v1")
        api_key = args.api_key or os.environ.get("OPENAI_API_KEY", "EMPTY")

        print(f"Using {args.model_type} model: {model_name}")
        print(f"API base URL: {api_base}")

        model = OpenAIChatModel(
            model_name=model_name,
            api_key=api_key,
            client_kwargs={"base_url": api_base},
        )
        formatter = OpenAIChatFormatter()
    else:
        raise ValueError(f"Unsupported model_type: {args.model_type}")
    toolkit = Toolkit()
    toolkit.register_tool_function(create_worker)
    # toolkit.register_tool_function(read_excel_file)

    # # Register xlsx skill if available
    # skill_dir = "./.claude/skills"
    # if os.path.exists(skill_dir):
    #     for skill_file in os.listdir(skill_dir):
    #         if skill_file.endswith(".md"):
    #             skill_path = os.path.join(skill_dir, skill_file)
    #             toolkit.register_agent_skill(skill_path)
    planner = ReActAgent(
        name="Friday",
        sys_prompt="""You are Friday, a multifunctional agent that can help people solving different complex tasks. You act like a meta planner to solve complicated tasks by decomposing the task and building/orchestrating different worker agents to finish the sub-tasks.

## Core Mission
Your primary purpose is to break down complicated tasks into manageable subtasks (a plan),
create worker agents to finish the subtask, and coordinate their execution to achieve the user's goal efficiently.
Sub-agents are equipped with various tools to handle different types of tasks.
### Important Constraints
1. DO NOT TRY TO SOLVE THE SUBTASKS DIRECTLY yourself.
2. Always follow the plan sequence.
3. DO NOT finish the plan until all subtasks are finished.
""",  # noqa: E501
        model=model,
        formatter=formatter,
        plan_notebook=PlanNotebook(),
        toolkit=toolkit,
        max_iters=20,
    )

    # Determine which samples to process
    if args.sample_idx is not None:
        # Single sample
        sample_indices = [args.sample_idx]
    else:
        # Batch processing
        start_idx = args.start_idx
        end_idx = args.end_idx if args.end_idx is not None else total_samples
        sample_indices = list(range(start_idx, min(end_idx, total_samples)))

    result_dir = Path(args.result_dir) if args.result_dir else None

    print(f"Processing {len(sample_indices)} sample(s) from GAIA validation set")
    print(f"Total samples in dataset: {total_samples}")
    print(f"Sample indices: {sample_indices}")

    # Check if there are any samples to process
    if len(sample_indices) == 0:
        print("❌ No samples to process!")
        print("\nPossible reasons:")
        if args.sample_idx is not None:
            print(f"1. Specified sample index {args.sample_idx} is out of range (total: {total_samples})")
            print(f"   Valid range: 0 to {total_samples - 1}")
        else:
            print(f"1. Start index {args.start_idx} is >= total samples ({total_samples})")
            if args.end_idx is not None:
                print(f"2. End index {args.end_idx} is <= start index {args.start_idx}")
            print(f"   Valid range: 0 to {total_samples - 1}")
        print("\nPlease check your --sample_idx, --start_idx, or --end_idx parameters.")
        return

    # Process each sample
    all_results = []
    for sample_idx in sample_indices:
        if sample_idx >= total_samples:
            print(f"Warning: Sample index {sample_idx} is out of range (total: {total_samples})")
            continue

        sample = ds[sample_idx]
        result = await process_sample(
            sample_idx=sample_idx,
            sample=sample,
            data_dir=data_dir,
            planner=planner,
            result_dir=result_dir,
        )
        all_results.append(result)

    # Save summary
    if result_dir:
        summary_file = result_dir / "summary.json"
        summary = {
            "total_processed": len(all_results),
            "successful": sum(1 for r in all_results if r.get("success", False)),
            "failed": sum(1 for r in all_results if not r.get("success", False)),
            "results": all_results,
        }
        with open(summary_file, "w", encoding="utf-8") as f:
            json.dump(summary, f, indent=2, ensure_ascii=False)
        print(f"\nSummary saved to {summary_file}")
        print(f"Total processed: {len(all_results)}")
        print(f"Successful: {summary['successful']}")
        print(f"Failed: {summary['failed']}")


asyncio.run(main())
