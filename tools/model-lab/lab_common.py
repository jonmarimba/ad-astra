"""Shared paths for model-lab. Standard library only."""
import os


def lab_home():
    """Where this machine keeps its profiles, seen list, run history and smoke results.
    $MODEL_LAB_HOME if set, else ~/.model-lab (the home folder on Windows, macOS and Linux alike).
    Nothing is written beside the code, so a checkout stays clean and can be read-only."""
    return os.environ.get("MODEL_LAB_HOME") or os.path.join(os.path.expanduser("~"), ".model-lab")


def hf_base():
    """The Hugging Face site. $MODEL_LAB_HF_BASE points the tools at a stub for tests or a mirror."""
    return (os.environ.get("MODEL_LAB_HF_BASE") or "https://huggingface.co").rstrip("/")


def llm_base(default="http://localhost:1234"):
    """The OpenAI-compatible server to measure. An empty $LLM_BASE counts as unset."""
    return (os.environ.get("LLM_BASE") or default).rstrip("/")
