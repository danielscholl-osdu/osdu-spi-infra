#  Copyright 2023 Google LLC
#  Copyright 2023 EPAM
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

from datetime import timedelta

import logging
import airflow
from airflow import DAG
from airflow.operators.python_operator import PythonOperator

logger = logging.getLogger(__name__)

default_args = {
    "start_date": airflow.utils.dates.days_ago(0),
    "retries": 0,
    "retry_delay": timedelta(seconds=30),
    "trigger_rule": "none_failed",
}


def list_packages():
    '''
        Function to print directories into logs
    '''
    import site
    import os

    path =  next(os.walk(site.getsitepackages()[0]))[1]
    for directories in path:
        logger.info(directories)


with DAG("Echo_DAG",
    default_args=default_args,
    description="A DAG for testing installed libs availability",
    schedule_interval=None,
    dagrun_timeout=timedelta(minutes=180)) as dag:
    packages_list_task = PythonOperator(task_id="list_packages_task", python_callable=list_packages)
