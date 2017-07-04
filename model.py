
# coding: utf-8

from sklearn.ensemble import GradientBoostingClassifier
from sklearn.cross_validation import KFold, cross_val_score
from sklearn.metrics import roc_auc_score
from sklearn.preprocessing import LabelEncoder, OneHotEncoder
from six.moves import cPickle as pickle
import numpy as np
import time
import datetime
import pandas as pd

# Preprocessing function
def fill_na_mean(df, col_names):
    for c in col_names:
        df[c] = df[c].fillna(df[c].mean())
    return df

# Read model from pickle

pickle_file = 'cancellations_model.pickle'

with open(pickle_file, 'rb') as f:
    save = pickle.load(f)
    model = save['model']
    print('Model Loaded')


# Prediction
# Считываем данные для предсказания, которые выдает запрос
features = pd.read_csv('input.csv', header = 0, index_col='order_id')

# Preprocessing
features = features.drop(['dow'], axis=1)
features = fill_na_mean(features, ['shifts_num', 'dow_paid_share'])
features = features.fillna(0)
y_pred = model.predict_proba(features)[:,1]

df = pd.DataFrame(index=features.index, columns=['will_cancel'])
df['will_cancel'] = model.predict_proba(features)[:,1]

df.to_csv('output.csv')
print('DONE')