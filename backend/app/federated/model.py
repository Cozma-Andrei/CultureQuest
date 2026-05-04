import tensorflow as tf
import numpy as np

# Input: user profile vector + context vector
# Output: relevance score [0, 1] for a cultural landmark
INPUT_DIM = 16
HIDDEN_DIMS = [64, 32]
OUTPUT_DIM = 1


def build_mlp() -> tf.keras.Model:
    """Build the MLP recommendation model."""
    pass


def get_model_weights(model: tf.keras.Model) -> list[np.ndarray]:
    return model.get_weights()


def set_model_weights(model: tf.keras.Model, weights: list[np.ndarray]) -> None:
    model.set_weights(weights)


def convert_to_tflite(model: tf.keras.Model) -> bytes:
    """Convert Keras model to TFLite for on-device inference."""
    pass
